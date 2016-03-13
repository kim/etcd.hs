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

-- | Contstruct an 'Env'ironment from just a URL of an etcd server
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
-- May throw 'HTTPException' if a transport error occurs or the server responds
-- with an unexpected status code. 'EtcdException' ('ClientError') will be
-- thrown if the server responds with invalid data (eg. because we're not
-- talking to an actual etcd server).
interpret :: (MonadIO m, MonadThrow m, HasEnv e) => e -> EtcdF (m a) -> m a
interpret env f = debugRq env f *> go f
  where
    runHttp
        :: ( MonadIO    m
           , MonadThrow m
           , Show a
           )
        => HTTP.Request
        -> (HTTP.Response Lazy.ByteString -> Either String a)
        -> m a
    runHttp      rq g = http env rq  >>= throwInvalidResponse . g >>= debugRs
    runHttpEmpty rq   = empty env rq >>= debugRs

    baseRq = view baseRequest env

    getKeyRq k ps
        = rqMethod GET
        . rqPath (keysPath <> encodeUtf8 k)
        . ignoreStatus
        . HTTP.setQueryString (toQuery ps)
        $ baseRq

    putKeyRq k ps
        = rqMethod PUT
        . rqPath (keysPath <> encodeUtf8 k)
        . ignoreStatus
        . HTTP.urlEncodedBody (mapMaybe (bitraverse Just id) (toQuery ps))
        $ baseRq

    postKeyRq k ps
        = rqMethod POST
        . rqPath (keysPath <> encodeUtf8 k)
        . ignoreStatus
        . HTTP.urlEncodedBody (mapMaybe (bitraverse Just id) (toQuery ps))
        $ baseRq

    delKeyRq k ps
        = rqMethod DELETE
        . rqPath (keysPath <> encodeUtf8 k)
        . ignoreStatus
        . HTTP.setQueryString (toQuery ps)
        $ baseRq

    watchKeyRq k ps
        = rqMethod GET
        . rqPath (keysPath <> encodeUtf8 k)
        . ignoreStatus
        . HTTP.setQueryString (toQuery ps)
        $ baseRq

    keyExistsRq k
        = rqMethod HEAD
        . rqPath (keysPath <> encodeUtf8 k)
        . ignoreStatus
        $ baseRq


    listMembersRq
        = rqMethod GET
        . rqPath membersPath
        $ baseRq

    addMemberRq us
        = rqMethod POST
        . rqPath membersPath
        . rqBdy (encode us)
        $ baseRq

    delMemberRq m
        = rqMethod DELETE
        . rqPath (membersPath <> encodeUtf8 m)
        $ baseRq

    updMemberRq m us
        = rqMethod PUT
        . rqPath (membersPath <> encodeUtf8 m)
        . rqBdy (encode us)
        $ baseRq

    leaderStatsRq = rqMethod GET . rqPath (statsPath <> "leader") $ baseRq
    selfStatsRq   = rqMethod GET . rqPath (statsPath <> "self")   $ baseRq
    storeStatsRq  = rqMethod GET . rqPath (statsPath <> "store")  $ baseRq

    versionRq = rqMethod GET . rqPath versionPath $ baseRq
    healthRq  = rqMethod GET . rqPath healthPath  $ baseRq

    go (GetKey    k ps next) = runHttp (getKeyRq  k ps) keyspaceRs >>= next
    go (PutKey    k ps next) = runHttp (putKeyRq  k ps) keyspaceRs >>= next
    go (PostKey   k ps next) = runHttp (postKeyRq k ps) keyspaceRs >>= next
    go (DeleteKey k ps next) = runHttp (delKeyRq  k ps) keyspaceRs >>= next
    go (WatchKey  k ps next)
        = runHttp (watchKeyRq k ps) Right
      >>= \case rs | emptyResponse rs -> go (WatchKey k ps next)
                   | otherwise        -> throwInvalidResponse (keyspaceRs rs)
                                     >>= next
    go (KeyExists k next)
        = runHttpEmpty (keyExistsRq k)
      >>= \rs -> case statusCode (HTTP.responseStatus rs) of
                     200 -> next True
                     404 -> next False
                     _   -> throwM $ HTTP.StatusCodeException
                                 (HTTP.responseStatus    rs)
                                 (HTTP.responseHeaders   rs)
                                 (HTTP.responseCookieJar rs)

    go (ListMembers       next) = runHttp listMembersRq    jsonRs >>= next
    go (AddMember      us next) = runHttp (addMemberRq us) jsonRs >>= next
    go (DeleteMember m    next) = runHttpEmpty (delMemberRq m)    >> next
    go (UpdateMember m us next) = runHttpEmpty (updMemberRq m us) >> next

    go (GetLeaderStats next) = runHttp leaderStatsRq jsonRs >>= next
    go (GetSelfStats   next) = runHttp selfStatsRq   jsonRs >>= next
    go (GetStoreStats  next) = runHttp storeStatsRq  jsonRs >>= next

    go (GetVersion next) = runHttp versionRq jsonRs >>= next
    go (GetHealth  next) = runHttp healthRq  jsonRs >>= next

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

    debugRs :: (Show a, MonadIO m) => a -> m a
    debugRs a = do
        tid <- liftIO myThreadId
        Log.debug (view logger env) $
            Log.field "thread" (show tid) . Log.field "response" (show a)
        return a


empty :: (MonadIO m, HasEnv e) => e -> Request -> m (HTTP.Response ())
empty env rq = runRq env rq HTTP.httpNoBody

http :: (MonadIO m, HasEnv e) => e -> Request -> m (HTTP.Response Lazy.ByteString)
http env rq = runRq env rq HTTP.httpLbs

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
        GetKey    k ps _ -> cmd "GetKey"    . key' k . params ps
        PutKey    k ps _ -> cmd "PutKey"    . key' k . params ps
        PostKey   k ps _ -> cmd "PostKey"   . key' k . params ps
        DeleteKey k ps _ -> cmd "DeleteKey" . key' k . params ps
        WatchKey  k ps _ -> cmd "WatchKey"  . key' k . params ps
        KeyExists k    _ -> cmd "KeyExists" . key' k

        ListMembers       _ -> cmd "ListMembers"
        AddMember   us    _ -> cmd "AddMember"    . purls us
        DeleteMember m    _ -> cmd "DeleteMember" . membr m
        UpdateMember m us _ -> cmd "UpdateMember" . membr m . purls us

        GetLeaderStats _ -> cmd "GetLeaderStats"
        GetSelfStats   _ -> cmd "GetSelfStats"
        GetStoreStats  _ -> cmd "GetStoreStats"
        GetVersion     _ -> cmd "GetVersion"
        GetHealth      _ -> cmd "GetHealth"
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
