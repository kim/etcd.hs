-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE DeriveFunctor              #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE UndecidableInstances       #-}

module Database.Etcd
    ( Env
    , HasEnv    (..)
    , Client
    , EtcdError (..)

    , mkEnv
    , runClient
    , runClient'
    )
where

import           Control.Lens                (Lens', view)
import           Control.Lens.TH             (makeLenses)
import           Control.Monad.Base
import           Control.Monad.Catch
import           Control.Monad.Free.Class
import           Control.Monad.IO.Class
import           Control.Monad.Reader
import           Control.Monad.Trans.Control
import           Control.Monad.Trans.Etcd
import           Data.Aeson                  (FromJSON, eitherDecode, encode)
import           Data.Bitraversable
import qualified Data.ByteString             as Strict
import           Data.ByteString.Conversion
import qualified Data.ByteString.Lazy        as Lazy
import           Data.Maybe
import           Data.Monoid
import           Data.Text.Encoding
import           Data.Typeable
import           Network.HTTP.Client         (Request (..))
import qualified Network.HTTP.Client         as HTTP
import           Network.HTTP.Types


data Env = Env
    { _baseReq :: !Request
    , _httpMgr :: !HTTP.Manager
    }
makeLenses ''Env

class HasEnv a where
    baseRequest :: Lens' a Request
    httpManager :: Lens' a HTTP.Manager

instance HasEnv Env where
    baseRequest = baseReq
    httpManager = httpMgr


data EtcdError = InvalidResponse String
    deriving (Eq, Show, Typeable)

instance Exception EtcdError

newtype Client e a = Client { client :: EtcdT (ReaderT e IO) a }
    deriving ( Functor
             , Applicative
             , Monad
             , MonadIO
             , MonadThrow
             , MonadCatch
             --, MonadReader e
             , MonadBase IO
             , MonadFree EtcdF
             )

instance MonadBaseControl IO (Client e) where
    type StM (Client e) a = StM (EtcdT (ReaderT e IO)) a

    liftBaseWith f = Client $ liftBaseWith $ \run -> f (run . client)
    restoreM       = Client . restoreM


runClient :: (MonadIO m, HasEnv e) => e -> Client e a -> m a
runClient e a = liftIO $ runReaderT (runEtcdT eval (client a)) e

runClient' :: (MonadIO m, MonadThrow m) => String -> Client Env a -> m a
runClient' url a = do
    mgr <- liftIO $ HTTP.newManager HTTP.defaultManagerSettings
    env <- mkEnv url mgr
    runClient env a


mkEnv :: MonadThrow m => String -> HTTP.Manager -> m Env
mkEnv url mgr = Env <$> HTTP.parseUrl url <*> pure mgr


eval :: ( MonadIO       m
        , MonadThrow    m
        , MonadReader e m
        , HasEnv      e
        )
     => EtcdF (m a)
     -> m a
eval f = view baseRequest >>= go f
  where
    go (GetKey k ps next) rq
        = http ( ignoreStatus
               . HTTP.setQueryString (toQuery ps)
               $ mkRq rq GET (keysPath <> encodeUtf8 k) Nothing)
      >>= throwInvalidResponse . keyspaceResponse
      >>= next
    go (PutKey k ps next) rq
        = http ( ignoreStatus
               . (\rq' -> rq' { method = "PUT" })
               . HTTP.urlEncodedBody (mapMaybe (bitraverse Just id) (toQuery ps))
               $ mkRq rq PUT (keysPath <> encodeUtf8 k) Nothing)
      >>= throwInvalidResponse . keyspaceResponse
      >>= next
    go (PostKey k ps next) rq
        = http ( ignoreStatus
               . HTTP.urlEncodedBody (mapMaybe (bitraverse Just id) (toQuery ps))
               $ mkRq rq POST (keysPath <> encodeUtf8 k) Nothing)
      >>= throwInvalidResponse . keyspaceResponse
      >>= next
    go (DeleteKey k ps next) rq
        = http ( ignoreStatus
               . HTTP.setQueryString (toQuery ps)
               $ mkRq rq DELETE (keysPath <> encodeUtf8 k) Nothing)
      >>= throwInvalidResponse . keyspaceResponse
      >>= next
    go (WatchKey k ps next) rq
        = http ( ignoreStatus
               . HTTP.setQueryString (toQuery ps)
               $ mkRq rq GET (keysPath <> encodeUtf8 k) Nothing)
      >>= \case rs | emptyResponse rs -> go (WatchKey k ps next) rq
                   | otherwise        -> throwInvalidResponse (keyspaceResponse rs)
                                     >>= next

    go (ListMembers next) rq
        = http (mkRq rq GET membersPath Nothing)
      >>= throwInvalidResponse . jsonResponse
      >>= next
    go (AddMember us next) rq
        = http (mkRq rq POST membersPath (Just (encode us)))
      >>= throwInvalidResponse . jsonResponse
      >>= next
    go (DeleteMember m next) rq
        = empty (mkRq rq DELETE (membersPath <> encodeUtf8 m) Nothing)
       >> next
    go (UpdateMember m us next) rq
        = empty (mkRq rq PUT (membersPath <> encodeUtf8 m) (Just (encode us)))
       >> next

    go (GetLeaderStats next) rq
        = http (mkRq rq GET (statsPath <> "leader") Nothing)
      >>= throwInvalidResponse . jsonResponse
      >>= next
    go (GetSelfStats   next) rq
        = http (mkRq rq GET (statsPath <> "self") Nothing)
      >>= throwInvalidResponse . jsonResponse
      >>= next
    go (GetStoreStats  next) rq
        = http (mkRq rq GET (statsPath <> "store") Nothing)
      >>= throwInvalidResponse . jsonResponse
      >>= next

    go (GetVersion next) rq
        = http (mkRq rq GET versionPath Nothing)
      >>= throwInvalidResponse . jsonResponse
      >>= next
    go (GetHealth  next) rq
        = http (mkRq rq GET healthPath Nothing)
      >>= throwInvalidResponse . jsonResponse
      >>= next

    emptyResponse r
        = statusIsSuccessful (HTTP.responseStatus r)
       && Lazy.null (HTTP.responseBody r)

    ignoreStatus rq = rq { checkStatus = \_ _ _ -> Nothing }


empty :: (MonadIO m, MonadReader e m, HasEnv e) => Request -> m ()
empty rq = view httpManager >>= liftIO . HTTP.httpNoBody rq >> return ()

http :: ( MonadIO       m
        , MonadReader e m
        , HasEnv      e
        )
     => Request
     -> m (HTTP.Response Lazy.ByteString)
http rq = view httpManager >>= liftIO . HTTP.httpLbs rq

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
throwInvalidResponse (Left  e) = throwM $ InvalidResponse e
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
