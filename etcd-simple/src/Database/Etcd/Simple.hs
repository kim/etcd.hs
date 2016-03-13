-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

module Database.Etcd.Simple
    ( Env
    , HasEnv (..)

    , mkEnv
    , mkEnv'

    , runEtcd
    , interpret

    , module Control.Monad.Etcd
    )
where

import           Control.Concurrent         (myThreadId)
import           Control.Lens               (Lens', lens, view)
import           Control.Monad.Catch
import           Control.Monad.Etcd
import           Control.Monad.IO.Class
import           Control.Monad.Trans.Etcd
import           Data.Aeson                 (eitherDecode, encode)
import           Data.Aeson.Types           (FromJSON, parseEither)
import           Data.Bitraversable
import qualified Data.ByteString            as Strict
import           Data.ByteString.Builder    (charUtf8, toLazyByteString)
import           Data.ByteString.Conversion
import qualified Data.ByteString.Lazy       as Lazy
import           Data.Etcd.Free
import           Data.List                  (intersperse)
import           Data.Maybe
import           Data.Monoid
import           Data.Text                  (pack)
import           Data.Text.Encoding
import           Network.HTTP.Client        (Request (..))
import qualified Network.HTTP.Client        as HTTP
import           Network.HTTP.Types
import qualified System.Logger              as Log


-- | The environment required for the interpreter
data Env = Env
    { _baseRequest :: !Request
    , _httpManager :: !HTTP.Manager
    , _logger      :: !Log.Logger
    }

-- | A generalization of the environment, such that it can be embedded in bigger
-- environments.
class HasEnv a where
    environment :: Lens' a Env

    baseRequest :: Lens' a Request
    baseRequest = environment . go
      where
        go = lens _baseRequest (\s a -> s { _baseRequest = a })

    httpManager :: Lens' a HTTP.Manager
    httpManager = environment . go
      where
        go = lens _httpManager (\s a -> s { _httpManager = a })

    logger      :: Lens' a Log.Logger
    logger      = environment . go
      where
        go = lens _logger (\s a -> s { _logger = a })

instance HasEnv Env where
    environment = id


-- | Contruct an 'Env'ironment
mkEnv :: MonadThrow m => String -> HTTP.Manager -> Log.Logger -> m Env
mkEnv url mgr lgr = Env <$> HTTP.parseUrl url <*> pure mgr <*> pure lgr

-- | Contstruct an 'Env'ironment from just the URL of an etcd server
mkEnv' :: (MonadIO m, MonadThrow m) => String -> m Env
mkEnv' url = do
    mgr <- liftIO $ HTTP.newManager HTTP.defaultManagerSettings
    lgr <- Log.new $ Log.setName (Just "etcd-simple") Log.defSettings
    mkEnv url mgr lgr

-- | Interpret a computation in the 'EtcdT' monad transformer
runEtcd :: (MonadIO m, MonadCatch m, HasEnv e) => e -> EtcdT m a -> m a
runEtcd e = runEtcdT (interpret e)

-- | An interpreter of the free monad over 'EtcdF'
--
-- May throw a 'HTTP.HTTPException' if a transport error occurs or the server
-- responds with an unexpected status code. A 'ClientError' will be thrown if
-- the server responds with invalid data (eg. because we're not talking to an
-- actual etcd server).
interpret :: (MonadIO m, MonadThrow m, HasEnv e) => e -> EtcdF (m a) -> m a
interpret env f = debugRq env f *> case f of
    Keyspace g -> keyspaceI env g
    Cluster  g -> clusterI  env g
    Stats    g -> statsI    env g
    Misc     g -> miscI     env g

keyspaceI :: (MonadIO m, MonadThrow m, HasEnv e) => e -> KeyspaceF (m a) -> m a
keyspaceI env = \case
    GetKey    k ps next -> runHttp env (getKeyRq  k ps) keyspaceRs >>= next
    PutKey    k ps next -> runHttp env (putKeyRq  k ps) keyspaceRs >>= next
    PostKey   k ps next -> runHttp env (postKeyRq k ps) keyspaceRs >>= next
    DeleteKey k ps next -> runHttp env (delKeyRq  k ps) keyspaceRs >>= next
    WatchKey  k ps next -> runHttp env (watchKeyRq k ps) Right
      >>= \case rs | emptyResponse rs -> keyspaceI env (WatchKey k ps next)
                   | otherwise        -> throwInvalidResponse (keyspaceRs rs)
                                     >>= next
    KeyExists k next    -> runHttpEmpty env (keyExistsRq k)
      >>= \rs -> case statusCode (HTTP.responseStatus rs) of
                     200 -> next True
                     404 -> next False
                     _   -> throwM $ HTTP.StatusCodeException
                                 (HTTP.responseStatus    rs)
                                 (HTTP.responseHeaders   rs)
                                 (HTTP.responseCookieJar rs)
  where
    getKeyRq k ps
        = rqMethod GET
        . rqPath (keysPath <> encodeUtf8 k)
        . ignoreStatus
        . HTTP.setQueryString (toQuery ps)
        $ view baseRequest env

    putKeyRq k ps
        = rqMethod PUT
        . rqPath (keysPath <> encodeUtf8 k)
        . ignoreStatus
        . HTTP.urlEncodedBody (mapMaybe (bitraverse Just id) (toQuery ps))
        $ view baseRequest env

    postKeyRq k ps
        = rqMethod POST
        . rqPath (keysPath <> encodeUtf8 k)
        . ignoreStatus
        . HTTP.urlEncodedBody (mapMaybe (bitraverse Just id) (toQuery ps))
        $ view baseRequest env

    delKeyRq k ps
        = rqMethod DELETE
        . rqPath (keysPath <> encodeUtf8 k)
        . ignoreStatus
        . HTTP.setQueryString (toQuery ps)
        $ view baseRequest env

    watchKeyRq k ps
        = rqMethod GET
        . rqPath (keysPath <> encodeUtf8 k)
        . ignoreStatus
        . HTTP.setQueryString (toQuery ps)
        $ view baseRequest env

    keyExistsRq k
        = rqMethod HEAD
        . rqPath (keysPath <> encodeUtf8 k)
        . ignoreStatus
        $ view baseRequest env

    -- A long-polling watch may be terminated by the server (or due to network
    -- failure) at any time. Since the response headers are sent immediately, we
    -- can detect this if we have a success HTTP status with an empty response
    -- body, and simply try again.
    emptyResponse r
        = statusIsSuccessful (HTTP.responseStatus r)
       && Lazy.null (HTTP.responseBody r)

    ignoreStatus rq = rq
        { checkStatus = \s h c ->
            if statusIsServerError s then checkStatus rq s h c else Nothing
        }

clusterI :: (MonadIO m, MonadThrow m, HasEnv e) => e -> ClusterF (m a) -> m a
clusterI env = \case
    ListMembers       next -> runHttp env listMembersRq    jsonRs >>= next
    AddMember      us next -> runHttp env (addMemberRq us) jsonRs >>= next
    DeleteMember m    next -> runHttpEmpty env (delMemberRq m)    >> next
    UpdateMember m us next -> runHttpEmpty env (updMemberRq m us) >> next
 where
    listMembersRq
        = rqMethod GET
        . rqPath membersPath
        $ view baseRequest env

    addMemberRq us
        = rqMethod POST
        . rqPath membersPath
        . rqBdy (encode us)
        $ view baseRequest env

    delMemberRq m
        = rqMethod DELETE
        . rqPath (membersPath <> encodeUtf8 m)
        $ view baseRequest env

    updMemberRq m us
        = rqMethod PUT
        . rqPath (membersPath <> encodeUtf8 m)
        . rqBdy (encode us)
        $ view baseRequest env

statsI :: (MonadIO m, MonadThrow m, HasEnv e) => e -> StatsF (m a) -> m a
statsI env = \case
    GetLeaderStats next -> runHttp env leaderStatsRq jsonRs >>= next
    GetSelfStats   next -> runHttp env selfStatsRq   jsonRs >>= next
    GetStoreStats  next -> runHttp env storeStatsRq  jsonRs >>= next
  where
    leaderStatsRq = rqMethod GET . rqPath (statsPath <> "leader") $ view baseRequest env
    selfStatsRq   = rqMethod GET . rqPath (statsPath <> "self")   $ view baseRequest env
    storeStatsRq  = rqMethod GET . rqPath (statsPath <> "store")  $ view baseRequest env

miscI :: (MonadIO m, MonadThrow m, HasEnv e) => e -> MiscF (m a) -> m a
miscI env = \case
    GetVersion next -> runHttp env versionRq jsonRs >>= next
    GetHealth  next -> runHttp env healthRq  jsonRs >>= next
  where
    versionRq = rqMethod GET . rqPath versionPath $ view baseRequest env
    healthRq  = rqMethod GET . rqPath healthPath  $ view baseRequest env


runHttp
    :: ( MonadIO    m
       , MonadThrow m
       , Show a
       , HasEnv e
       )
    => e
    -> HTTP.Request
    -> (HTTP.Response Lazy.ByteString -> Either String a)
    -> m a
runHttp env rq g = runRq env rq HTTP.httpLbs >>= throwInvalidResponse . g >>= debugRs env

runHttpEmpty :: (MonadIO m, HasEnv e) => e -> HTTP.Request -> m (HTTP.Response ())
runHttpEmpty env rq = runRq env rq HTTP.httpNoBody >>= debugRs env

runRq :: (MonadIO m, HasEnv e, Show a)
      => e
      -> Request
      -> (Request -> HTTP.Manager -> IO (HTTP.Response a))
      -> m (HTTP.Response a)
runRq env rq f = do
    Log.trace lgr (Log.msg (show rq))
    rs <- liftIO $ f rq mgr
    Log.trace lgr (Log.msg (show rs))
    return rs
  where
    lgr = view logger      env
    mgr = view httpManager env

rqMethod :: StdMethod -> Request -> Request
rqMethod m rq = rq { method = renderStdMethod m }

rqPath :: Strict.ByteString -> Request -> Request
rqPath p rq = rq { path = p }

rqBdy :: Lazy.ByteString -> Request -> Request
rqBdy b rq =  rq { requestBody = HTTP.RequestBodyLBS b }

keysPath :: Strict.ByteString
keysPath = "/v2/keys/"

membersPath :: Strict.ByteString
membersPath = "/v2/members/"

statsPath :: Strict.ByteString
statsPath = "/v2/stats/"

versionPath :: Strict.ByteString
versionPath = "/version"

healthPath :: Strict.ByteString
healthPath = "/health"

throwInvalidResponse :: MonadThrow m => Either String b -> m b
throwInvalidResponse (Left  e) = throwM $ ClientError (pack e)
throwInvalidResponse (Right r) = pure r

keyspaceRs :: HTTP.Response Lazy.ByteString -> Either String Response
keyspaceRs rs = do
    let hdrs = HTTP.responseHeaders rs
        bdy  = HTTP.responseBody    rs
    cid <- let h = "x-etcd-cluster-id" in expect h (header h hdrs)
    idx <- let h = "x-etcd-index"      in expect h (header h hdrs)
    let meta = ResponseMeta
                 { _etcdClusterId = cid
                 , _etcdIndex     = idx
                 , _raftIndex     = header "x-raft-index" hdrs
                 , _raftTerm      = header "x-raft-term"  hdrs
                 }
    rsb <- parseEither rsFromJSON =<< eitherDecode bdy
    pure $ either (Left . Rs meta) (Right . Rs meta) rsb
  where
    header h hs  = fromByteString =<< lookup h hs
    expect h     = maybe (Left (unexpected h)) Right
    unexpected h = "Unexpected response: Header " ++ show h ++ " not present"

jsonRs :: FromJSON a => HTTP.Response Lazy.ByteString -> Either String a
jsonRs = eitherDecode . HTTP.responseBody


debugRq :: (MonadIO m, HasEnv e) => e -> EtcdF a -> m ()
debugRq env f = do
    let lgr = view logger env
    tid <- liftIO myThreadId
    Log.debug lgr $ Log.field "thread" (show tid) . case f of
        Keyspace (GetKey    k ps _) -> cmd "GetKey"    . key' k . params ps
        Keyspace (PutKey    k ps _) -> cmd "PutKey"    . key' k . params ps
        Keyspace (PostKey   k ps _) -> cmd "PostKey"   . key' k . params ps
        Keyspace (DeleteKey k ps _) -> cmd "DeleteKey" . key' k . params ps
        Keyspace (WatchKey  k ps _) -> cmd "WatchKey"  . key' k . params ps
        Keyspace (KeyExists k    _) -> cmd "KeyExists" . key' k

        Cluster (ListMembers       _) -> cmd "ListMembers"
        Cluster (AddMember   us    _) -> cmd "AddMember"    . purls us
        Cluster (DeleteMember m    _) -> cmd "DeleteMember" . membr m
        Cluster (UpdateMember m us _) -> cmd "UpdateMember" . membr m . purls us

        Stats (GetLeaderStats _) -> cmd "GetLeaderStats"
        Stats (GetSelfStats   _) -> cmd "GetSelfStats"
        Stats (GetStoreStats  _) -> cmd "GetStoreStats"

        Misc (GetVersion _) -> cmd "GetVersion"
        Misc (GetHealth  _) -> cmd "GetHealth"
  where
    cmd :: Strict.ByteString -> (Log.Msg -> Log.Msg)
    cmd = Log.field "command"

    key' = Log.field "key"

    params :: Show a => a -> (Log.Msg -> Log.Msg)
    params = Log.field "params" . show

    purls
        = Log.field "peerURLs"
        . toLazyByteString
        . mconcat . intersperse (charUtf8 ',')
        . map (builder . fromURL)
        . peerURLs

    membr = Log.field "member"

debugRs :: (Show a, MonadIO m, HasEnv e) => e -> a -> m a
debugRs env a = do
    tid <- liftIO myThreadId
    Log.debug (view logger env) $
        Log.field "thread" (show tid) . Log.field "response" (show a)
    return a

