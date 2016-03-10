-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE UndecidableInstances       #-}
{-# LANGUAGE ViewPatterns               #-}

module Database.Etcd.Simple
    ( Env
    , HasEnv      (..)
    , Client
    , EtcdError   (..)
    , MonadClient (..)

    , mkEnv
    , mkEnv'
    , runClient
    , runClient'

    , runEtcdIO

    , module Control.Monad.Trans.Etcd
    )
where

import           Control.Concurrent          (myThreadId)
import           Control.Lens                (Lens', lens, view)
import           Control.Monad.Base
import           Control.Monad.Catch
import           Control.Monad.Etcd.Class
import           Control.Monad.IO.Class
import           Control.Monad.Reader
import           Control.Monad.Trans.Control
import           Control.Monad.Trans.Etcd
import           Control.Monad.Trans.Free
import           Data.Aeson                  (eitherDecode, encode)
import           Data.Aeson.Types            (FromJSON, parseEither)
import           Data.Bitraversable
import qualified Data.ByteString             as Strict
import           Data.ByteString.Builder     (charUtf8, toLazyByteString)
import           Data.ByteString.Conversion
import qualified Data.ByteString.Lazy        as Lazy
import           Data.List                   (intersperse)
import           Data.Maybe
import           Data.Monoid
import           Data.Text                   (pack)
import           Data.Text.Encoding
import           Network.HTTP.Client         (Request (..))
import qualified Network.HTTP.Client         as HTTP
import           Network.HTTP.Types
import qualified System.Logger               as Log
import           System.Logger.Class         hiding (eval)


data Env = Env
    { _baseRequest :: !Request
    , _httpManager :: !HTTP.Manager
    , _logger      :: !Log.Logger
    }

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


newtype Client a = Client { client :: ReaderT Env IO a }
    deriving ( Functor
             , Applicative
             , Monad
             , MonadIO
             , MonadBase IO
             , MonadThrow
             , MonadCatch
             , MonadReader Env
             )

instance MonadBaseControl IO Client where
    type StM Client a = StM (ReaderT Env IO) a

    liftBaseWith f = Client $ liftBaseWith $ \run -> f (run . client)
    restoreM       = Client . restoreM

instance MonadLogger Client where
    log l m = view logger >>= \lgr -> Log.log lgr l m

class ( Functor      m
      , Applicative  m
      , Monad        m
      , MonadIO      m
      , MonadCatch   m
      )
      => MonadClient m
  where
    liftClient :: Client a -> m a

instance MonadClient Client where
    liftClient = id

instance MonadEtcd Client where
    liftEtcd m = view environment >>= \e -> iterT (runEtcdIO e) m


runClient :: (MonadIO m, HasEnv e) => e -> Client a -> m a
runClient (view environment -> e) (client -> a) = liftIO $ runReaderT a e

runClient' :: (MonadIO m, MonadCatch m) => String -> Client a -> m a
runClient' url a = mkEnv' url >>= (`runClient` a)

mkEnv :: MonadThrow m => String -> HTTP.Manager -> Log.Logger -> m Env
mkEnv url mgr lgr = Env <$> HTTP.parseUrl url <*> pure mgr <*> pure lgr

mkEnv' :: (MonadIO m, MonadThrow m) => String -> m Env
mkEnv' url = do
    mgr <- liftIO $ HTTP.newManager HTTP.defaultManagerSettings
    lgr <- Log.new $ Log.setName (Just "etcd-simple") Log.defSettings
    mkEnv url mgr lgr


runEtcdIO :: (MonadIO m, MonadThrow m, HasEnv e) => e -> EtcdF (m a) -> m a
runEtcdIO env f = debugRq env f *> go f
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
        = ignoreStatus
        . HTTP.setQueryString (toQuery ps)
        $ mkRq baseRq GET (keysPath <> encodeUtf8 k)

    putKeyRq k ps
        = ignoreStatus
        . (\rq' -> rq' { method = "PUT" })
        . HTTP.urlEncodedBody (mapMaybe (bitraverse Just id) (toQuery ps))
        $ mkRq baseRq PUT (keysPath <> encodeUtf8 k)

    postKeyRq k ps
        = ignoreStatus
        . HTTP.urlEncodedBody (mapMaybe (bitraverse Just id) (toQuery ps))
        $ mkRq baseRq POST (keysPath <> encodeUtf8 k)

    delKeyRq k ps
        = ignoreStatus
        . HTTP.setQueryString (toQuery ps)
        $ mkRq baseRq DELETE (keysPath <> encodeUtf8 k)

    watchKeyRq k ps
        = ignoreStatus
        . HTTP.setQueryString (toQuery ps)
        $ mkRq baseRq GET (keysPath <> encodeUtf8 k)

    keyExistsRq k
        = ignoreStatus
        $ mkRq baseRq HEAD (keysPath <> encodeUtf8 k)

    listMembersRq    = mkRq baseRq GET membersPath
    addMemberRq   us = rqBdy (encode us) $ mkRq baseRq POST membersPath
    delMemberRq m    = mkRq baseRq DELETE (membersPath <> encodeUtf8 m)
    updMemberRq m us = rqBdy (encode us)
                     $ mkRq baseRq PUT (membersPath <> encodeUtf8 m)

    leaderStatsRq = mkRq baseRq GET (statsPath <> "leader")
    selfStatsRq   = mkRq baseRq GET (statsPath <> "self")
    storeStatsRq  = mkRq baseRq GET (statsPath <> "store")

    versionRq = mkRq baseRq GET versionPath
    healthRq  = mkRq baseRq GET healthPath

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

    emptyResponse r
        = statusIsSuccessful (HTTP.responseStatus r)
       && Lazy.null (HTTP.responseBody r)

    ignoreStatus rq = rq { checkStatus = \_ _ _ -> Nothing }

    debugRs :: (Show a, MonadIO m) => a -> m a
    debugRs a = do
        tid <- liftIO myThreadId
        Log.debug (view logger env) $
            Log.field "thread" (show tid) . Log.field "response" (show a)
        return a


empty :: (MonadIO m, HasEnv e) => e -> Request -> m (HTTP.Response ())
empty env rq = liftIO $ HTTP.httpNoBody rq (view httpManager env)

http :: (MonadIO m, HasEnv e) => e -> Request -> m (HTTP.Response Lazy.ByteString)
http env rq = do
    let lgr = view logger       env
        mgr = view httpManager  env
    Log.trace lgr (Log.msg (show rq))
    rs  <- liftIO $ HTTP.httpLbs rq mgr
    Log.trace lgr (Log.msg (show rs))
    return rs

mkRq :: Request -> StdMethod -> Strict.ByteString -> Request
mkRq base m p = base
    { method      = renderStdMethod m
    , path        = p
    }

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
