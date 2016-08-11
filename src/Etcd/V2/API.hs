{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators     #-}

module Etcd.V2.API where

import           Control.Applicative
import qualified Data.Aeson          as Aeson
import           Data.Aeson.Types    hiding (Value)
import           Data.Char
import           Data.HashMap.Strict (HashMap)
import           Data.Proxy
import           Data.Text           (Text)
import qualified Data.Text           as Text
import           Data.Time           (UTCTime)
import           Data.Word
import           GHC.Generics
import           Servant.API


type Versioned = "v2"

type PutCreated = Verb 'PUT  201
type Head       = Verb 'HEAD 200

type EtcdAPI = KeyspaceAPI :<|> MembersAPI :<|> AdminAPI :<|> StatsAPI

etcdAPI :: Proxy EtcdAPI
etcdAPI = Proxy

--------------------------------------------------------------------------------
-- Keyspace API (aka Client API)
--------------------------------------------------------------------------------

type KeyspaceResponseHeaders
    = Headers '[ Header "X-Etcd-Cluster-ID" Text
               , Header "X-Etcd-Index"      Word64
               , Header "X-Raft-Index"      Word64
               , Header "X-Raft-Term"       Word64
               ]

type KeyspaceResponse = KeyspaceResponseHeaders Response

type KeyspaceAPI = Versioned :> "keys" :>
    (     Capture    "key"       Text
       :> QueryParam "value"     Value
       :> QueryParam "ttl"       SetTTL
       :> QueryParam "prevValue" Value
       :> QueryParam "prevIndex" Word64
       :> QueryParam "prevExist" Bool
       :> QueryParam "refresh"   Bool
       :> QueryParam "dir"       Bool
       :> PutCreated '[JSON] KeyspaceResponse
  :<|>    Capture    "key"       Text
       :> QueryParam "value"     Value
       :> QueryParam "ttl"       TTL
       :> PostCreated '[JSON] KeyspaceResponse
  :<|>    Capture    "key"       Text
       :> QueryParam "recursive" Bool
       :> QueryParam "sorted"    Bool
       :> QueryParam "quorum"    Bool
       :> QueryParam "wait"      Bool
       :> QueryParam "waitIndex" Word64
       :> Get '[JSON] KeyspaceResponse
  :<|>    Capture    "key"       Text
       :> QueryParam "recursive" Bool
       :> QueryParam "prevValue" Value
       :> QueryParam "prevIndex" Word64
       :> QueryParam "dir"       Bool
       :> Delete '[JSON] KeyspaceResponse
  :<|>    Capture    "key"       Text
       :> Head '[JSON] (KeyspaceResponseHeaders NoContent)
    )

keyspaceAPI :: Proxy KeyspaceAPI
keyspaceAPI = Proxy

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


type Response = SuccessResponse

data SuccessResponse = SuccessResponse
    { _rsAction   :: !Action
    , _rsNode     :: !Node
    , _rsPrevNode :: Maybe Node
    } deriving (Eq, Show, Generic)

instance FromJSON SuccessResponse where parseJSON = gParsePrefixed

-- | _Some_ error responses contain a response body like this.
data ErrorResponse = ErrorResponse
    { _rsErrorCode :: !Word16
    , _rsMessage   :: !Text
    , _rsCause     :: !Text
    , _rsIndex     :: !Word64
    } deriving (Eq, Show, Generic)

instance FromJSON ErrorResponse where parseJSON = gParsePrefixed


--------------------------------------------------------------------------------
-- Members API
--------------------------------------------------------------------------------

type MembersAPI = Versioned :> "members" :>
    (  Get '[JSON] Members
  :<|> ReqBody '[JSON] PeerURLs :> PostCreated '[JSON] Member
  :<|> Capture "id" Text :> DeleteNoContent '[JSON] NoContent
  :<|> Capture "id" Text :> ReqBody '[JSON] PeerURLs :> PutNoContent '[JSON] NoContent
    )

membersAPI :: Proxy MembersAPI
membersAPI = Proxy

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

type AdminAPI
     = "version" :> Get '[JSON] Version
  :<|> "health"  :> Get '[JSON] Health

adminAPI :: Proxy AdminAPI
adminAPI = Proxy

data Version = Version
    { etcdcluster :: !Text
    , etcdversion :: !Text
    } deriving (Show, Generic)

instance FromJSON Version

newtype Health = Health { health :: Bool }
    deriving (Show, Generic)

instance FromJSON Health


--------------------------------------------------------------------------------
-- Stats API
--------------------------------------------------------------------------------

type StatsAPI = Versioned :> "stats" :>
    (  "leader" :> Get '[JSON] LeaderStats
  :<|> "self"   :> Get '[JSON] SelfStats
  :<|> "store"  :> Get '[JSON] StoreStats
    )

statsAPI :: Proxy StatsAPI
statsAPI = Proxy

data LeaderStats = LeaderStats
    { _lsLeader    :: !Text
    , _lsFollowers :: !(HashMap Text FollowerStats)
    } deriving (Show, Generic)

instance FromJSON LeaderStats where parseJSON = gParsePrefixed


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
