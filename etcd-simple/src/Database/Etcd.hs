-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE TemplateHaskell       #-}

module Database.Etcd
    ( Client
    , EtcdError       (..)

    , runClient
    , runClient'

    -- * Keys
    , Node            (..)
    , Response        (..)
    , SuccessResponse (..)
    , ErrorResponse   (..)
    , Key
    , Value
    , TTL             (..)
    , get
    , set
    , update
    , rm
    , rmr
    , rmdir
    , mkdir
    , watch
    , watcher
    , refresh
    , casVal
    , casIdx
    , cadVal
    , cadIdx

    -- * Members
    , Members         (..)
    , Member          (..)
    , URL             (..)
    , PeerURLs        (..)
    , listMembers
    , addMember
    , deleteMember
    , updateMember

    -- * Stats
    , LeaderStats     (..)
    , FollowerStats   (..)
    , FollowerCounts  (..)
    , FollowerLatency (..)
    , SelfStats       (..)
    , LeaderInfo      (..)
    , StoreStats      (..)
    , getLeaderStats
    , getSelfStats
    , getStoreStats

    -- * Misc
    , Version         (..)
    , Health          (..)
    , getVersion
    , getHealth
    )
where

import           Control.Lens               (view)
import           Control.Lens.TH            (makeLenses)
import           Control.Monad.Catch
import           Control.Monad.IO.Class
import           Control.Monad.Operational  hiding (view)
import           Control.Monad.Reader
import           Data.Aeson                 (FromJSON (..), eitherDecode, encode)
import           Data.Bitraversable
import           Data.ByteString            (ByteString)
import           Data.ByteString.Conversion
import qualified Data.ByteString.Lazy       as Lazy
import           Data.Etcd
import           Data.Maybe
import           Data.Monoid
import           Data.Text.Encoding
import           Data.Typeable
import           Network.HTTP.Client        (Request (..))
import qualified Network.HTTP.Client        as HTTP
import           Network.HTTP.Types


data Env = Env
    { _baseReq :: !Request
    , _httpMgr :: !HTTP.Manager
    }

makeLenses ''Env


data EtcdError = InvalidResponse String
    deriving (Eq, Show, Typeable)

instance Exception EtcdError


type Client = ReaderT Env

runClient
    :: ( MonadIO     m
       , MonadThrow  m
       , EvalEtcdAPI f
       )
    => String
    -> f (Client m) b
    -> m b
runClient url f = do
    mgr <- liftIO $ HTTP.newManager HTTP.defaultManagerSettings
    runClient' url mgr f

runClient'
    :: ( MonadIO     m
       , MonadThrow  m
       , EvalEtcdAPI f
       )
    => String
    -> HTTP.Manager
    -> f (ReaderT Env m) b
    -> m b
runClient' url mgr f = mkEnv >>= runReaderT (eval f)
  where
    mkEnv = do
        rq <- HTTP.parseUrl url
        pure Env
            { _baseReq = rq { checkStatus = \_ _ _ -> Nothing }
            , _httpMgr = mgr
            }

    eval = evalEtcd EtcdAPI
        { evalKeysAPI    = runKeysAPI
        , evalMembersAPI = runMembersAPI
        , evalStatsAPI   = runStatsAPI
        , evalMiscAPI    = runMiscAPI
        }

runKeysAPI
    :: ( MonadIO         m
       , MonadThrow      m
       , MonadReader Env m
       )
    => KeysAPI m a
    -> m a
runKeysAPI = eval <=< viewT
  where
    eval (Return              x) = return x
    eval (i@(Get    _ _) :>>= k) = go i >>= runKeysAPI . k
    eval (i@(Put    _ _) :>>= k) = go i >>= runKeysAPI . k
    eval (i@(Delete _ _) :>>= k) = go i >>= runKeysAPI . k

    go f = do
        rq <- view baseReq
        rs <- http (request f rq)
        if emptyResponse rs
            then go f
            else either (throwM . InvalidResponse) pure (response rs)

    endpoint :: ByteString
    endpoint = "/v2/keys"

    request :: KeysF a -> Request -> Request
    request (Get key' ps) rq
        = HTTP.setQueryString (either toQuery toQuery ps)
        $ rq { method = "GET"
             , path   = endpoint <> "/" <> encodeUtf8 key'
             }
    request (Put key' ps) rq
        = (\rq' -> rq' { method = "PUT"
                       , path   = endpoint <> "/" <> encodeUtf8 key'
                       })
        . HTTP.urlEncodedBody (mapMaybe (bitraverse Just id) (toQuery ps))
        $ rq
    request (Delete key' ps) rq
        = HTTP.setQueryString (toQuery ps)
        $ rq { method = "DELETE"
             , path   = endpoint <> "/" <> encodeUtf8 key'
             }

    response :: HTTP.Response Lazy.ByteString -> Either String Response
    response rs = do
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

    emptyResponse r
        = statusIsSuccessful (HTTP.responseStatus r)
       && Lazy.null (HTTP.responseBody r)

    header h hs  = fromByteString =<< lookup h hs
    expect h     = maybe (Left (unexpected h)) Right
    unexpected h = "Unexpected response: Header " ++ show h ++ " not present"

runStatsAPI
    :: ( MonadIO         m
       , MonadThrow      m
       , MonadReader Env m
       )
    => StatsAPI m a
    -> m a
runStatsAPI = eval <=< viewT
  where
    eval (Return                x) = return x
    eval (i@GetLeaderStats :>>= k) = json (request i) >>= runStatsAPI . k
    eval (i@GetSelfStats   :>>= k) = json (request i) >>= runStatsAPI . k
    eval (i@GetStoreStats  :>>= k) = json (request i) >>= runStatsAPI . k

    endpoint :: ByteString
    endpoint = "/v2/stats"

    request :: StatsF a -> Request -> Request
    request GetLeaderStats rq = rq { method = "GET", path = endpoint <> "/leader" }
    request GetSelfStats   rq = rq { method = "GET", path = endpoint <> "/self"   }
    request GetStoreStats  rq = rq { method = "GET", path = endpoint <> "/store"  }

runMembersAPI
    :: ( MonadIO         m
       , MonadThrow      m
       , MonadReader Env m
       )
    => MembersAPI m a
    -> m a
runMembersAPI = eval <=< viewT
  where
    eval (Return                    x) = return x
    eval (i@ListMembers        :>>= k) = json (request i) >>= runMembersAPI . k
    eval (i@(AddMember      _) :>>= k) = json (request i) >>= runMembersAPI . k
    eval (i@(DeleteMember   _) :>>= k) = nb i >>= runMembersAPI . k
    eval (i@(UpdateMember _ _) :>>= k) = nb i >>= runMembersAPI . k

    nb f = do
        rq  <- view baseReq
        mgr <- view httpMgr
        liftIO (HTTP.httpNoBody (request f rq) mgr) *> pure ()

    endpoint :: ByteString
    endpoint = "/v2/members"

    request :: MembersF a -> Request -> Request
    request ListMembers rq = rq
        { method = "GET"
        , path   = endpoint
        }
    request (AddMember us) rq = rq
        { method = "POST"
        , path   = endpoint
        , requestBody = HTTP.RequestBodyLBS (encode us)
        }
    request (DeleteMember m) rq = rq
        { method = "DELETE"
        , path   = endpoint <> "/" <> encodeUtf8 m
        }
    request (UpdateMember m us) rq = rq
        { method = "PUT"
        , path   = endpoint <> "/" <> encodeUtf8 m
        , requestBody = HTTP.RequestBodyLBS (encode us)
        }

runMiscAPI
    :: ( MonadIO         m
       , MonadThrow      m
       , MonadReader Env m
       )
    => MiscAPI m a
    -> m a
runMiscAPI = eval <=< viewT
  where
    eval (Return            x) = return x
    eval (i@GetVersion :>>= k) = json (request i) >>= runMiscAPI . k
    eval (i@GetHealth  :>>= k) = json (request i) >>= runMiscAPI . k

    request :: MiscF a -> Request -> Request
    request GetVersion rq = rq { method = "GET", path = "/version" }
    request GetHealth  rq = rq { method = "GET", path = "/health"  }


json :: ( MonadIO         m
        , MonadThrow      m
        , MonadReader Env m
        , FromJSON    a
        )
     => (Request -> Request)
     -> m a
json mkRq = do
    rq <- view baseReq
    rs <- eitherDecode . HTTP.responseBody <$> http (mkRq rq)
    either (throwM . InvalidResponse) pure rs

http :: (MonadIO m, MonadReader Env m) => Request -> m (HTTP.Response Lazy.ByteString)
http rq = view httpMgr >>= liftIO . HTTP.httpLbs rq
