-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE DeriveFunctor              #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE UndecidableInstances       #-}
{-# LANGUAGE ViewPatterns               #-}

module Database.Etcd
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

import           Control.Concurrent           (myThreadId)
import           Control.Lens                 (Lens', lens, view)
import           Control.Monad.Catch
import           Control.Monad.Free.Class
import           Control.Monad.IO.Class
import           Control.Monad.Reader
import qualified Control.Monad.RWS.Lazy       as LRW
import qualified Control.Monad.RWS.Strict     as RW
import qualified Control.Monad.State.Lazy     as LS
import qualified Control.Monad.State.Strict   as S
import           Control.Monad.Trans.Etcd
import           Control.Monad.Trans.Except   (ExceptT)
import           Control.Monad.Trans.Identity (IdentityT)
import           Control.Monad.Trans.List     (ListT)
import           Control.Monad.Trans.Maybe    (MaybeT)
import qualified Control.Monad.Writer.Lazy    as LW
import qualified Control.Monad.Writer.Strict  as W
import           Data.Aeson                   (FromJSON, eitherDecode, encode)
import           Data.Bitraversable
import qualified Data.ByteString              as Strict
import           Data.ByteString.Builder      (charUtf8, toLazyByteString)
import           Data.ByteString.Conversion
import qualified Data.ByteString.Lazy         as Lazy
import           Data.List                    (intersperse)
import           Data.Maybe
import           Data.Monoid
import           Data.Text                    (pack)
import           Data.Text.Encoding
import           Network.HTTP.Client          (Request (..))
import qualified Network.HTTP.Client          as HTTP
import           Network.HTTP.Types
import qualified System.Logger                as Log
import           System.Logger.Class          hiding (eval)


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


newtype Client a = Client { client :: ReaderT Env (EtcdT IO) a }
    deriving ( Functor
             , Applicative
             , Monad
             , MonadIO
             , MonadThrow
             , MonadCatch
             , MonadReader Env
             , MonadFree   EtcdF
             )

instance MonadLogger Client where
    log l m = view logger >>= \lgr -> Log.log lgr l m


class ( Functor         m
      , Applicative     m
      , Monad           m
      , MonadIO         m
      , MonadCatch      m
      , MonadReader Env m
      )
      => MonadClient m
  where
    liftClient :: Client a -> m a

instance MonadClient Client where
    liftClient = id

instance            MonadClient m  => MonadClient (IdentityT        m) where liftClient = lift . liftClient
instance            MonadClient m  => MonadClient (ListT            m) where liftClient = lift . liftClient
instance            MonadClient m  => MonadClient (MaybeT           m) where liftClient = lift . liftClient
instance            MonadClient m  => MonadClient (ExceptT        e m) where liftClient = lift . liftClient
instance            MonadClient m  => MonadClient (ReaderT      Env m) where liftClient = lift . liftClient
instance            MonadClient m  => MonadClient (S.StateT       s m) where liftClient = lift . liftClient
instance            MonadClient m  => MonadClient (LS.StateT      s m) where liftClient = lift . liftClient
instance (Monoid w, MonadClient m) => MonadClient (W.WriterT    w   m) where liftClient = lift . liftClient
instance (Monoid w, MonadClient m) => MonadClient (LW.WriterT   w   m) where liftClient = lift . liftClient
instance (Monoid w, MonadClient m) => MonadClient (RW.RWST  Env w s m) where liftClient = lift . liftClient
instance (Monoid w, MonadClient m) => MonadClient (LRW.RWST Env w s m) where liftClient = lift . liftClient


runClient :: (MonadIO m, HasEnv e) => e -> Client a -> m a
runClient (view environment -> e) a = liftIO $
    runEtcdT (runEtcdIO e) (runReaderT (client a) e)

runClient' :: (MonadIO m, MonadCatch m) => String -> Client a -> m a
runClient' url a = mkEnv' url >>= (`runClient` a)

mkEnv :: MonadThrow m => String -> HTTP.Manager -> Log.Logger -> m Env
mkEnv url mgr lgr = Env <$> HTTP.parseUrl url <*> pure mgr <*> pure lgr

mkEnv' :: (MonadIO m, MonadThrow m) => String -> m Env
mkEnv' url = do
    mgr <- liftIO $ HTTP.newManager HTTP.defaultManagerSettings
    lgr <- Log.new $ Log.setName (Just "etcd-simple") Log.defSettings
    mkEnv url mgr lgr


runEtcdIO :: (MonadIO m, MonadThrow m) => Env -> EtcdF (m a) -> m a
runEtcdIO env f = debugRq env f *> go f (view baseRequest env)
  where
    go (GetKey k ps next) rq
        = http env ( ignoreStatus
                   . HTTP.setQueryString (toQuery ps)
                   $ mkRq rq GET (keysPath <> encodeUtf8 k) Nothing)
      >>= throwInvalidResponse . keyspaceResponse
      >>= debugRs
      >>= next
    go (PutKey k ps next) rq
        = http env ( ignoreStatus
                   . (\rq' -> rq' { method = "PUT" })
                   . HTTP.urlEncodedBody (mapMaybe (bitraverse Just id) (toQuery ps))
                   $ mkRq rq PUT (keysPath <> encodeUtf8 k) Nothing)
      >>= throwInvalidResponse . keyspaceResponse
      >>= debugRs
      >>= next
    go (PostKey k ps next) rq
        = http env ( ignoreStatus
                   . HTTP.urlEncodedBody (mapMaybe (bitraverse Just id) (toQuery ps))
                   $ mkRq rq POST (keysPath <> encodeUtf8 k) Nothing)
      >>= throwInvalidResponse . keyspaceResponse
      >>= debugRs
      >>= next
    go (DeleteKey k ps next) rq
        = http env ( ignoreStatus
                   . HTTP.setQueryString (toQuery ps)
                   $ mkRq rq DELETE (keysPath <> encodeUtf8 k) Nothing)
      >>= throwInvalidResponse . keyspaceResponse
      >>= debugRs
      >>= next
    go (WatchKey k ps next) rq
        = http env ( ignoreStatus
                   . HTTP.setQueryString (toQuery ps)
                   $ mkRq rq GET (keysPath <> encodeUtf8 k) Nothing)
      >>= \case rs | emptyResponse rs -> go (WatchKey k ps next) rq
                   | otherwise        -> throwInvalidResponse (keyspaceResponse rs)
                                     >>= debugRs
                                     >>= next

    go (ListMembers next) rq
        = http env (mkRq rq GET membersPath Nothing)
      >>= throwInvalidResponse . jsonResponse
      >>= debugRs
      >>= next
    go (AddMember us next) rq
        = http env (mkRq rq POST membersPath (Just (encode us)))
      >>= throwInvalidResponse . jsonResponse
      >>= debugRs
      >>= next
    go (DeleteMember m next) rq
        = empty env (mkRq rq DELETE (membersPath <> encodeUtf8 m) Nothing)
       >> next
    go (UpdateMember m us next) rq
        = empty env (mkRq rq PUT (membersPath <> encodeUtf8 m) (Just (encode us)))
       >> next

    go (GetLeaderStats next) rq
        = http env (mkRq rq GET (statsPath <> "leader") Nothing)
      >>= throwInvalidResponse . jsonResponse
      >>= debugRs
      >>= next
    go (GetSelfStats   next) rq
        = http env (mkRq rq GET (statsPath <> "self") Nothing)
      >>= throwInvalidResponse . jsonResponse
      >>= debugRs
      >>= next
    go (GetStoreStats  next) rq
        = http env (mkRq rq GET (statsPath <> "store") Nothing)
      >>= throwInvalidResponse . jsonResponse
      >>= debugRs
      >>= next

    go (GetVersion next) rq
        = http env (mkRq rq GET versionPath Nothing)
      >>= throwInvalidResponse . jsonResponse
      >>= debugRs
      >>= next
    go (GetHealth  next) rq
        = http env (mkRq rq GET healthPath Nothing)
      >>= throwInvalidResponse . jsonResponse
      >>= debugRs
      >>= next

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


empty :: MonadIO m => Env -> Request -> m ()
empty env rq = liftIO $ HTTP.httpNoBody rq (view httpManager env) >> return ()

http :: MonadIO m => Env -> Request -> m (HTTP.Response Lazy.ByteString)
http env rq = do
    let lgr = view logger       env
        mgr = view httpManager  env
    Log.trace lgr (Log.msg (show rq))
    rs  <- liftIO $ HTTP.httpLbs rq mgr
    Log.trace lgr (Log.msg (show rs))
    return rs

mkRq :: Request -> StdMethod -> Strict.ByteString -> Maybe Lazy.ByteString -> Request
mkRq base m p b = base
    { method      = renderStdMethod m
    , path        = p
    , requestBody = maybe mempty HTTP.RequestBodyLBS b
    }

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

keyspaceResponse :: HTTP.Response Lazy.ByteString -> Either String Response
keyspaceResponse rs = do
    let hdrs = HTTP.responseHeaders rs
        bdy  = HTTP.responseBody    rs
    cid <- let h = "x-etcd-cluster-id" in expect h (header h hdrs)
    idx <- let h = "x-etcd-index"      in expect h (header h hdrs)
    rsb <- eitherDecode bdy
    pure Response
        { etcdClusterId = cid
        , etcdIndex     = idx
        , raftIndex     = header "x-raft-index" hdrs
        , raftTerm      = header "x-raft-term"  hdrs
        , responseBody  = rsb
        }
  where
    header h hs  = fromByteString =<< lookup h hs
    expect h     = maybe (Left (unexpected h)) Right
    unexpected h = "Unexpected response: Header " ++ show h ++ " not present"

jsonResponse :: FromJSON a => HTTP.Response Lazy.ByteString -> Either String a
jsonResponse = eitherDecode . HTTP.responseBody


debugRq :: MonadIO m => Env -> EtcdF a -> m ()
debugRq env f = do
    let lgr = view logger env
    tid <- liftIO myThreadId
    Log.debug lgr $ Log.field "thread" (show tid) . case f of
        GetKey    k ps _ -> cmd "GetKey"    . key' k . params ps
        PutKey    k ps _ -> cmd "PutKey"    . key' k . params ps
        PostKey   k ps _ -> cmd "PostKey"   . key' k . params ps
        DeleteKey k ps _ -> cmd "DeleteKey" . key' k . params ps
        WatchKey  k ps _ -> cmd "WatchKey"  . key' k . params ps

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
