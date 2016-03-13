-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}

module Data.Etcd.Types
    ( Key
    , Value
    , TTL
    , SetTTL          (..)
    , EtcdError       (..)

      -- * Keyspace API
      -- ** Response Types
    , Response
    , Rs              (..)
    , rsFromJSON
    , Node            (..)
    , Action          (..)
    , ResponseMeta    (..)
    , SuccessResponse (..)
    , ErrorResponse   (..)

    , hoistError

     -- ** Request Parameters
    , GetOptions      (..)
    , getOptions
    , PutOptions      (..)
    , putOptions
    , PostOptions     (..)
    , postOptions
    , DeleteOptions   (..)
    , deleteOptions
    , WatchOptions    (_watchRecursive, _watchWaitIndex)
    , watchOptions

      -- * Members API
    , Members         (..)
    , MemberId
    , Member          (..)
    , URL             (..)
    , PeerURLs        (..)

      -- * Stats API
    , LeaderStats     (..)
    , FollowerStats   (..)
    , FollowerCounts  (..)
    , FollowerLatency (..)
    , SelfStats       (..)
    , LeaderInfo      (..)
    , StoreStats      (..)

      -- * Misc API
    , Version         (..)
    , Health          (..)
    )
where

import           Control.Applicative
import           Control.Monad.Catch
import qualified Data.Aeson                   as Aeson
import           Data.Aeson.Types             hiding (Value)
import           Data.ByteString.Conversion   (toByteString')
import           Data.Etcd.Internal
import           Data.HashMap.Strict          (HashMap)
import           Data.Maybe                   (catMaybes)
import           Data.Text                    (Text)
import           Data.Time
import           Data.Word                    (Word16, Word64)
import           GHC.Generics
import           Network.HTTP.Types.QueryLike
import           Network.HTTP.Types.URI       (simpleQueryToQuery)


data EtcdError
    = EtcdError   (Rs ErrorResponse)
    | ClientError Text
    deriving (Eq, Show)

instance Exception EtcdError

--------------------------------------------------------------------------------
-- Keyspace
--------------------------------------------------------------------------------

type Key   = Text
type Value = Text

type TTL = Word64

data SetTTL = NoTTL | SomeTTL !TTL
    deriving Show

instance QueryValueLike SetTTL where
    toQueryValue NoTTL       = Nothing
    toQueryValue (SomeTTL n) = Just (toByteString' n)


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


type Response = Either (Rs ErrorResponse) (Rs SuccessResponse)

data ResponseMeta = ResponseMeta
    { _etcdClusterId :: !Text
    , _etcdIndex     :: !Word64
    , _raftIndex     :: !(Maybe Word64)
    , _raftTerm      :: !(Maybe Word64)
    } deriving (Eq, Show)

data Rs a = Rs
    { _rsMeta :: !ResponseMeta
    , _rsBody :: !a
    } deriving (Eq, Show)

instance Functor Rs where
    fmap f (Rs m b) = Rs m (f b)

rsFromJSON :: Aeson.Value -> Parser (Either ErrorResponse SuccessResponse)
rsFromJSON v = (Right <$> parseJSON v) <|> (Left <$> parseJSON v)

hoistError :: MonadThrow m => Response -> m (Rs SuccessResponse)
hoistError = either (throwM . EtcdError) return

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

data SuccessResponse = SuccessResponse
    { _rsAction   :: !Action
    , _rsNode     :: !Node
    , _rsPrevNode :: Maybe Node
    } deriving (Eq, Show, Generic)

instance FromJSON SuccessResponse

data ErrorResponse = ErrorResponse
    { _rsErrorCode :: !Word16
    , _rsMessage   :: !Text
    , _rsCause     :: !Text
    , _rsIndex     :: !Word64
    } deriving (Eq, Show, Generic)

instance FromJSON ErrorResponse

data GetOptions = GetOptions
    { _getRecursive :: !Bool
    , _getSorted    :: !Bool
    , _getQuorum    :: !Bool
    } deriving Show

instance QueryLike GetOptions where
    toQuery (GetOptions r s q) = simpleQueryToQuery
        [ ("recursive", toByteString' r)
        , ("sorted"   , toByteString' s)
        , ("quorum"   , toByteString' q)
        ]

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

instance QueryLike PutOptions where
    toQuery (PutOptions v t pV pI pE r d) = catMaybes
        [ (,) "value"     . toQueryValue . toByteString' <$> v
        , (,) "ttl"       . toQueryValue <$> t
        , (,) "prevValue" . toQueryValue . toByteString' <$> pV
        , (,) "prevIndex" . toQueryValue . toByteString' <$> pI
        , (,) "prevExist" . toQueryValue . toByteString' <$> pE
        , if r then Just ("refresh", Just "true") else Nothing
        , if d then Just ("dir"    , Just "true") else Nothing
        ]

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

instance QueryLike PostOptions where
    toQuery (PostOptions v t) = catMaybes
        [ (,) "value" . toQueryValue . toByteString' <$> v
        , (,) "ttl"   . toQueryValue . toByteString' <$> t
        ]

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

instance QueryLike DeleteOptions where
    toQuery (DeleteOptions r pV pI d) = catMaybes
        [ Just ("recursive", toQueryValue (toByteString' r))
        , (,) "prevValue" . toQueryValue . toByteString' <$> pV
        , (,) "prevIndex" . toQueryValue . toByteString' <$> pI
        , Just ("dir"      , toQueryValue (toByteString' d))
        ]

deleteOptions :: DeleteOptions
deleteOptions = DeleteOptions
    { _delRecursive = False
    , _delPrevValue = Nothing
    , _delPrevIndex = Nothing
    , _delDir       = False
    }

data WatchOptions = WatchOptions
    { _watchWait      :: !Bool -- nb. always 'True'
    , _watchRecursive :: !Bool
    , _watchWaitIndex :: Maybe Word64
    } deriving Show

instance QueryLike WatchOptions where
    toQuery (WatchOptions _ r aI) = catMaybes
        [ Just ("wait", Just "true")
        , Just ("recursive", toQueryValue (toByteString' r))
        , (,) "waitIndex" . toQueryValue . toByteString' <$> aI
        ]

watchOptions :: WatchOptions
watchOptions = WatchOptions
    { _watchWait      = True
    , _watchRecursive = False
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
-- Stats
--------------------------------------------------------------------------------

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
-- Misc
--------------------------------------------------------------------------------

data Version = Version
    { etcdcluster :: !Text
    , etcdversion :: !Text
    } deriving (Show, Generic)

instance FromJSON Version

newtype Health = Health { health :: Bool }
    deriving (Show, Generic)

instance FromJSON Health
