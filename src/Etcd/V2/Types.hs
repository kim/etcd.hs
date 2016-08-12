-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE OverloadedStrings #-}

module Etcd.V2.Types where

import           Control.Exception
import qualified Data.Aeson           as Aeson (Value)
import           Data.Aeson.Types     hiding (Value)
import qualified Data.ByteString.Lazy as Lazy (ByteString)
import           Data.Char
import           Data.HashMap.Strict  (HashMap)
import           Data.Text            (Text)
import qualified Data.Text            as Text (empty)
import           Data.Time            (UTCTime)
import           Data.Typeable
import           Data.Word
import           GHC.Generics
import           Network.HTTP.Client  (Manager)
import qualified Network.HTTP.Types   as HTTP (Status)
import           Servant.API          (ToHttpApiData (..))
import           Servant.Client       (BaseUrl)


data Env = Env
    { _envManager :: !Manager
    , _envBaseUrl :: !BaseUrl
    }

--------------------------------------------------------------------------------
-- Errors
--------------------------------------------------------------------------------

data EtcdError
    = EtcdError
        { etcdErrorResponse :: ErrorResponse }
    | HttpError
        { responseStatus :: HTTP.Status
        , responseBody   :: Lazy.ByteString
        }
    | DecodeError
        { decodeError  :: String
        , responseBody :: Lazy.ByteString
        }
    | TransportError
        { transportError :: SomeException }
    | UnexpectedError
        { unexpectedError :: SomeException }
    deriving (Show, Typeable)

instance Eq EtcdError where
    EtcdError      a   == EtcdError      x   = a == x
    HttpError      a b == HttpError      x y = (a, b) == (x, y)
    DecodeError    a b == DecodeError    x y = (a, b) == (x, y)
    TransportError a   == TransportError x   = show a == show x
    _ == _ = False

instance Exception EtcdError


--------------------------------------------------------------------------------
-- Keyspace API
--------------------------------------------------------------------------------

type Key   = Text
type Value = Text

type TTL = Word64

data SetTTL = NoTTL | SomeTTL !TTL
    deriving Show

instance ToHttpApiData SetTTL where
    toQueryParam NoTTL       = Text.empty
    toQueryParam (SomeTTL n) = toQueryParam n


data Node = Node
    { _nodeKey           :: !Text
    , _nodeDir           :: !Bool
    , _nodeValue         :: Maybe Text
    , _nodeNodes         :: [Node]
    , _nodeCreatedIndex  :: !Word64
    , _nodeModifiedIndex :: !Word64
    , _nodeExpiration    :: Maybe UTCTime
    , _nodeTTL           :: Maybe TTL
    } deriving (Eq, Show)

instance FromJSON Node where
    parseJSON = withObject "Node" $ \o ->
        Node <$> o .:  "key"
             <*> o .:? "dir"           .!= False
             <*> o .:? "value"
             <*> o .:? "nodes"         .!= []
             <*> o .:  "createdIndex"
             <*> o .:  "modifiedIndex"
             <*> o .:? "expiration"
             <*> o .:? "ttl"

-- | As defined in ${ETCD}/store/event.go
data Action
    = ActionGet
    | ActionCreate
    | ActionSet
    | ActionUpdate
    | ActionDelete
    | ActionCompareAndSwap
    | ActionCompareAndDelete
    | ActionExpire
    deriving (Eq, Show, Generic)

instance FromJSON Action where
    parseJSON = genericParseJSON defaultOptions
        { allNullaryToStringTag  = True
        , constructorTagModifier = stripFieldPrefix . drop 1
        }


type SuccessResponse = Response

data Response = Response
    { _rsAction   :: !Action
    , _rsNode     :: !Node
    , _rsPrevNode :: Maybe Node
    } deriving (Eq, Show, Generic)

instance FromJSON Response where parseJSON = gParsePrefixed

-- | _Some_ error responses contain a response body like this.
data ErrorResponse = ErrorResponse
    { _rsErrorCode :: !Word16
    , _rsMessage   :: !Text
    , _rsCause     :: !Text
    , _rsIndex     :: !Word64
    } deriving (Eq, Show, Generic)

instance FromJSON ErrorResponse where parseJSON = gParsePrefixed

data ResponseHeaders = ResponseHeaders
    { _rsEtcdClusterID :: !Text
    , _rsEtcdIndex     :: !Word64
    , _rsRaftIndex     :: !Word64
    , _rsRaftTerm      :: !Word64
    } deriving (Eq, Show)

data ResponseAndMetadata = ResponseAndMetadata
    { _rsResponse :: !Response
    , _rsMetadata :: Maybe ResponseHeaders
    } deriving (Eq, Show)

data GetOptions = GetOptions
    { _getRecursive :: !Bool
    , _getSorted    :: !Bool
    , _getQuorum    :: !Bool
    } deriving Show

getOptions :: GetOptions
getOptions = GetOptions
    { _getRecursive = False
    , _getSorted    = False
    , _getQuorum    = False
    }

data PutOptions = PutOptions
    { _putValue     :: Maybe Text
    , _putTTL       :: Maybe SetTTL
    , _putPrevValue :: Maybe Text
    , _putPrevIndex :: Maybe Word64
    , _putPrevExist :: Maybe Bool -- ^ 'Nothing' = don't care
    , _putRefresh   :: !Bool
    , _putDir       :: !Bool
    } deriving Show

putOptions :: PutOptions
putOptions = PutOptions
    { _putValue     = Nothing
    , _putTTL       = Nothing
    , _putPrevValue = Nothing
    , _putPrevIndex = Nothing
    , _putPrevExist = Nothing
    , _putRefresh   = False
    , _putDir       = False
    }

data PostOptions = PostOptions
    { _postValue :: Maybe Text
    , _postTTL   :: Maybe TTL
    } deriving Show

postOptions :: PostOptions
postOptions = PostOptions
    { _postValue = Nothing
    , _postTTL   = Nothing
    }

data DeleteOptions = DeleteOptions
    { _delRecursive :: !Bool
    , _delPrevValue :: Maybe Text
    , _delPrevIndex :: Maybe Word64
    , _delDir       :: !Bool
    } deriving Show

deleteOptions :: DeleteOptions
deleteOptions = DeleteOptions
    { _delRecursive = False
    , _delPrevValue = Nothing
    , _delPrevIndex = Nothing
    , _delDir       = False
    }

data WatchOptions = WatchOptions
    { _watchRecursive :: !Bool
    , _watchWaitIndex :: Maybe Word64
    } deriving Show

watchOptions :: WatchOptions
watchOptions = WatchOptions
    { _watchRecursive = False
    , _watchWaitIndex = Nothing
    }

--------------------------------------------------------------------------------
-- Members API
--------------------------------------------------------------------------------

newtype Members = Members { members :: [Member] }
    deriving (Show, Generic)

instance FromJSON Members

type MemberId = Text

data Member = Member
    { _mId         :: Maybe MemberId
    , _mName       :: Maybe Text
    , _mPeerURLs   :: [URL]
    , _mClientURLs :: Maybe [URL]
    } deriving (Show, Generic)

instance FromJSON Member where parseJSON = gParsePrefixed

instance ToJSON Member where
    toJSON = genericToJSON defaultOptions
        { fieldLabelModifier = stripFieldPrefix
        , omitNothingFields  = True
        }


newtype URL = URL { fromURL :: Text }
    deriving (Eq, Show)

instance FromJSON URL where
    parseJSON = withText "URL" $ pure . URL

instance ToJSON URL where
    toJSON = String . fromURL


newtype PeerURLs = PeerURLs { peerURLs :: [URL] }
    deriving (Eq, Show, Generic)

instance FromJSON PeerURLs
instance ToJSON   PeerURLs


--------------------------------------------------------------------------------
-- Admin API
--------------------------------------------------------------------------------

data Version = Version
    { etcdserver  :: !Text
    , etcdcluster :: !Text
    } deriving (Show, Generic)

instance FromJSON Version

newtype Health = Health { health :: Bool }
    deriving (Show, Generic)

instance FromJSON Health where
    parseJSON = withObject "Health" $ \obj -> do
        val <- obj .: "health"
        case val of
            "true"  -> pure $ Health True
            "false" -> pure $ Health False
            _       -> typeMismatch "Unkown `Health` value" (String val)

data LeaderStats = LeaderStats
    { _lsLeader    :: !Text
    , _lsFollowers :: !(HashMap Text FollowerStats)
    } deriving (Show, Generic)

instance FromJSON LeaderStats where parseJSON = gParsePrefixed


--------------------------------------------------------------------------------
-- Stats API
--------------------------------------------------------------------------------

data FollowerStats = FollowerStats
    { _fsCounts  :: !FollowerCounts
    , _fsLatency :: !FollowerLatency
    } deriving (Show, Generic)

instance FromJSON FollowerStats where parseJSON = gParsePrefixed


data FollowerCounts = FollowerCounts
    { _fcFail    :: !Word64
    , _fcSuccess :: !Word64
    } deriving (Show, Generic)

instance FromJSON FollowerCounts where parseJSON = gParsePrefixed


data FollowerLatency = FollowerLatency
    { _flAverage           :: !Double
    , _flCurrent           :: !Double
    , _flMaximum           :: !Double
    , _flMinimum           :: !Double
    , _flStandardDeviation :: !Double
    } deriving (Show, Generic)

instance FromJSON FollowerLatency where parseJSON = gParsePrefixed


data SelfStats = SelfStats
    { _ssId                   :: !Text
    , _ssLeaderInfo           :: !LeaderInfo
    , _ssName                 :: !Text
    , _ssRecvAppendRequestCnt :: !Word64
    , _ssRecvBandwidthRate    :: !Double
    , _ssRecvPkgRate          :: !Double
    , _ssSendAppendRequestCnt :: !Word64
    , _ssStartTime            :: !UTCTime
    , _ssState                :: !Text -- todo
    } deriving (Show, Generic)

instance FromJSON SelfStats where parseJSON = gParsePrefixed


data LeaderInfo = LeaderInfo
    { _liLeader    :: !Text
    , _liStartTime :: !UTCTime
    , _liUptime    :: !Text -- todo
    } deriving (Show, Generic)

instance FromJSON LeaderInfo where parseJSON = gParsePrefixed


data StoreStats = StoreStats
    { _stsCompareAndSwapFail    :: !Word64
    , _stsCompareAndSwapSuccess :: !Word64
    , _stsCreateFail            :: !Word64
    , _stsCreateSuccess         :: !Word64
    , _stsDeleteFail            :: !Word64
    , _stsDeleteSuccess         :: !Word64
    , _stsExpireCount           :: !Word64
    , _stsGetsFail              :: !Word64
    , _stsGetsSuccess           :: !Word64
    , _stsSetsFail              :: !Word64
    , _stsSetsSuccess           :: !Word64
    , _stsUpdateFail            :: !Word64
    , _stsUpdateSuccess         :: !Word64
    , _stsWatchers              :: !Word64
    } deriving (Show, Generic)

instance FromJSON StoreStats where parseJSON = gParsePrefixed


--------------------------------------------------------------------------------
-- Internal
--------------------------------------------------------------------------------

gParsePrefixed :: (Generic a, GFromJSON (Rep a)) => Aeson.Value -> Parser a
gParsePrefixed = genericParseJSON defaultOptions
    { fieldLabelModifier = stripFieldPrefix
    }

stripFieldPrefix :: String -> String
stripFieldPrefix ('_':s) = stripFieldPrefix s
stripFieldPrefix s       = case dropWhile isLower s of
    []     -> []
    (x:xs) -> toLower x : xs
