-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE GADTs             #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

module Data.Etcd.Keys
    ( -- * Types
      KeysAPI
    , KeysF           (..)
    , Node            (..)
    , Response        (..)
    , ResponseBody    (..)
    , SuccessResponse (..)
    , ErrorResponse   (..)
    , _Success
    , _Error

    , _KeyNotFound
    , _TestFailed
    , _NotFile
    , _NotDir
    , _NodeExist
    , _RootOnly
    , _DirNotEmpty
    , _Unauthorized
    , _PrevValueRequired
    , _TTLNaN
    , _IndexNaN
    , _InvalidField
    , _RaftInternal
    , _LeaderElect
    , _WatcherCleared
    , _EventIndexCleared

    , Key
    , Value
    , TTL             (..)

    , GetOptions
    , getOptions
    , gRecursive
    , gSorted
    , gQuorum

    , PutOptions
    , putOptions
    , pValue
    , pTTL
    , pPrevValue
    , pPrevIndex
    , pPrevExist
    , pRefresh
    , pDir

    , PostOptions
    , postOptions
    , cValue
    , cTTL

    , DeleteOptions
    , deleteOptions
    , dRecursive
    , dPrevValue
    , dPrevIndex
    , dDir

    , WatchOptions
    , watchOptions
    , wRecursive
    , wAfterIndex

      -- * KeysAPI
    , get
    , get'
    , set
    , update
    , rm
    , rmr
    , rmdir
    , mkdir
    , createInOrder
    , watch
    , watcher
    , refresh
    , casVal
    , casIdx
    , cadVal
    , cadIdx
    )
where

import Control.Applicative
import Control.Monad.Operational
import Data.Aeson                    hiding (Error, Success, Value)
import Data.ByteString.Conversion.To
import Data.Etcd.Internal
import Data.Function                 ((&))
import Data.Int
import Data.Maybe
import Data.Monoid                   (First)
import Data.Profunctor               (Choice)
import Data.Text                     (Text)
import Data.Time
import Data.Word
import GHC.Generics
import Network.HTTP.Types.QueryLike
import Network.HTTP.Types.URI


type KeysAPI = ProgramT KeysF

data KeysF a where
    Get    :: Key -> Either WatchOptions GetOptions -> KeysF Response
    Put    :: Key -> PutOptions                     -> KeysF Response
    Post   :: Key -> PostOptions                    -> KeysF Response
    Delete :: Key -> DeleteOptions                  -> KeysF Response

data GetOptions = GetOptions
    { _gRecursive :: !Bool
    , _gSorted    :: !Bool
    , _gQuorum    :: !Bool
    } deriving Show

getOptions :: GetOptions
getOptions = GetOptions
    { _gRecursive = False
    , _gSorted    = False
    , _gQuorum    = False
    }

gRecursive :: Lens' GetOptions Bool
gRecursive = lens _gRecursive (\s a -> s { _gRecursive = a })

gSorted :: Lens' GetOptions Bool
gSorted = lens _gSorted (\s a -> s { _gSorted = a })

gQuorum :: Lens' GetOptions Bool
gQuorum = lens _gQuorum (\s a -> s { _gQuorum = a })

instance QueryLike GetOptions where
    toQuery (GetOptions r s q) = simpleQueryToQuery
        [ ("recursive", toByteString' r)
        , ("sorted"   , toByteString' s)
        , ("quorum"   , toByteString' q)
        ]


data PutOptions = PutOptions
    { _pValue     :: Maybe Text
    , _pTTL       :: Maybe TTL
    , _pPrevValue :: Maybe Text
    , _pPrevIndex :: Maybe Word64
    , _pPrevExist :: Maybe Bool -- ^ 'Nothing' = don't care
    , _pRefresh   :: !Bool
    , _pDir       :: !Bool
    } deriving Show

putOptions :: PutOptions
putOptions = PutOptions
    { _pValue     = Nothing
    , _pTTL       = Nothing
    , _pPrevValue = Nothing
    , _pPrevIndex = Nothing
    , _pPrevExist = Nothing
    , _pRefresh   = False
    , _pDir       = False
    }

pValue :: Lens' PutOptions (Maybe Value)
pValue = lens _pValue (\s a -> s { _pValue = a })

pTTL :: Lens' PutOptions (Maybe TTL)
pTTL = lens _pTTL (\s a -> s { _pTTL = a })

pPrevValue :: Lens' PutOptions (Maybe Value)
pPrevValue = lens _pPrevValue (\s a -> s { _pPrevValue = a })

pPrevIndex :: Lens' PutOptions (Maybe Word64)
pPrevIndex = lens _pPrevIndex (\s a -> s { _pPrevIndex = a })

pPrevExist :: Lens' PutOptions (Maybe Bool)
pPrevExist = lens _pPrevExist (\s a -> s { _pPrevExist = a })

pRefresh :: Lens' PutOptions Bool
pRefresh = lens _pRefresh (\s a -> s { _pRefresh = a })

pDir :: Lens' PutOptions Bool
pDir = lens _pDir (\s a -> s { _pDir = a })

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

data PostOptions = PostOptions
    { _cValue :: Maybe Text
    , _cTTL   :: Maybe Word64
    } deriving Show

postOptions :: PostOptions
postOptions = PostOptions
    { _cValue = Nothing
    , _cTTL   = Nothing
    }

cValue :: Lens' PostOptions (Maybe Text)
cValue = lens _cValue (\s a -> s { _cValue = a })

cTTL :: Lens' PostOptions (Maybe Word64)
cTTL = lens _cTTL (\s a -> s { _cTTL = a })

instance QueryLike PostOptions where
    toQuery (PostOptions v t) = catMaybes
        [ (,) "value" . toQueryValue . toByteString' <$> v
        , (,) "ttl"   . toQueryValue . toByteString' <$> t
        ]


data DeleteOptions = DeleteOptions
    { _dRecursive :: !Bool
    , _dPrevValue :: Maybe Text
    , _dPrevIndex :: Maybe Word64
    , _dDir       :: !Bool
    } deriving Show

deleteOptions :: DeleteOptions
deleteOptions = DeleteOptions
    { _dRecursive = False
    , _dPrevValue = Nothing
    , _dPrevIndex = Nothing
    , _dDir       = False
    }

dRecursive :: Lens' DeleteOptions Bool
dRecursive = lens _dRecursive (\s a -> s { _dRecursive = a })

dPrevValue :: Lens' DeleteOptions (Maybe Value)
dPrevValue = lens _dPrevValue (\s a -> s { _dPrevValue = a })

dPrevIndex :: Lens' DeleteOptions (Maybe Word64)
dPrevIndex = lens _dPrevIndex (\s a -> s { _dPrevIndex = a })

dDir :: Lens' DeleteOptions Bool
dDir = lens _dDir (\s a -> s { _dDir = a })

instance QueryLike DeleteOptions where
    toQuery (DeleteOptions r pV pI d) = catMaybes
        [ Just ("recursive", toQueryValue (toByteString' r))
        , (,) "prevValue" . toQueryValue . toByteString' <$> pV
        , (,) "prevIndex" . toQueryValue . toByteString' <$> pI
        , Just ("dir"      , toQueryValue (toByteString' d))
        ]


data WatchOptions = WatchOptions
    { _wWait       :: !Bool -- nb. always 'True'
    , _wRecursive  :: !Bool
    , _wAfterIndex :: Maybe Word64
    } deriving Show

watchOptions :: WatchOptions
watchOptions = WatchOptions
    { _wWait       = True
    , _wRecursive  = False
    , _wAfterIndex = Nothing
    }

wRecursive :: Lens' WatchOptions Bool
wRecursive = lens _wRecursive (\s a -> s { _wRecursive = a })

wAfterIndex :: Lens' WatchOptions (Maybe Word64)
wAfterIndex = lens _wAfterIndex (\s a -> s { _wAfterIndex = a })

instance QueryLike WatchOptions where
    toQuery (WatchOptions _ r aI) = catMaybes
        [ Just ("wait", Just "true")
        , Just ("recursive", toQueryValue (toByteString' r))
        , (,) "afterIndex" . toQueryValue . toByteString' <$> aI
        ]

data Node = Node
    { key           :: !Text
    , dir           :: Bool
    , value         :: Maybe Text
    , nodes         :: [Node]
    , createdIndex  :: !Word64
    , modifiedIndex :: !Word64
    , expiration    :: Maybe UTCTime
    , ttl           :: Maybe Int64
    } deriving (Eq, Show, Generic)

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

data Response = Response
    { etcdClusterId :: !Text
    , etcdIndex     :: !Word64
    , raftIndex     :: Maybe Word64
    , raftTerm      :: Maybe Word64
    , responseBody  :: !ResponseBody
    } deriving (Eq, Show)

data ResponseBody
    = Success !SuccessResponse
    | Error   !ErrorResponse
    deriving (Eq, Show)

instance FromJSON ResponseBody where
    parseJSON v = (Success <$> parseJSON v) <|> (Error <$> parseJSON v)

_Success :: Prism' ResponseBody SuccessResponse
_Success = prism Success $ \case
    Success r -> Right r
    x         -> Left  x

_Error :: Prism' ResponseBody ErrorResponse
_Error = prism Error $ \case
    Error r -> Right r
    x       -> Left  x

data SuccessResponse = SuccessResponse
    { action   :: !Text
    , node     :: !Node
    , prevNode :: Maybe Node
    } deriving (Eq, Show, Generic)

instance FromJSON SuccessResponse

data ErrorResponse = ErrorResponse
    { errorCode :: !Word16
    , message   :: !Text
    , cause     :: !Text
    , index     :: !Word64
    } deriving (Eq, Show, Generic)

instance FromJSON ErrorResponse

_KeyNotFound :: Getting (First ErrorResponse) ResponseBody ErrorResponse
_KeyNotFound = _Error . hasCode 100

_TestFailed :: Getting (First ErrorResponse) ResponseBody ErrorResponse
_TestFailed = _Error . hasCode 101

_NotFile :: Getting (First ErrorResponse) ResponseBody ErrorResponse
_NotFile = _Error . hasCode 102

_NotDir :: Getting (First ErrorResponse) ResponseBody ErrorResponse
_NotDir = _Error . hasCode 104

_NodeExist :: Getting (First ErrorResponse) ResponseBody ErrorResponse
_NodeExist = _Error . hasCode 105

_RootOnly :: Getting (First ErrorResponse) ResponseBody ErrorResponse
_RootOnly = _Error . hasCode 107

_DirNotEmpty :: Getting (First ErrorResponse) ResponseBody ErrorResponse
_DirNotEmpty = _Error . hasCode 108

_Unauthorized :: Getting (First ErrorResponse) ResponseBody ErrorResponse
_Unauthorized = _Error . hasCode 110

_PrevValueRequired :: Getting (First ErrorResponse) ResponseBody ErrorResponse
_PrevValueRequired = _Error . hasCode 201

_TTLNaN :: Getting (First ErrorResponse) ResponseBody ErrorResponse
_TTLNaN = _Error . hasCode 202

_IndexNaN :: Getting (First ErrorResponse) ResponseBody ErrorResponse
_IndexNaN = _Error . hasCode 203

_InvalidField :: Getting (First ErrorResponse) ResponseBody ErrorResponse
_InvalidField = _Error . hasCode 209

_RaftInternal :: Getting (First ErrorResponse) ResponseBody ErrorResponse
_RaftInternal = _Error . hasCode 300

_LeaderElect :: Getting (First ErrorResponse) ResponseBody ErrorResponse
_LeaderElect = _Error . hasCode 301

_WatcherCleared :: Getting (First ErrorResponse) ResponseBody ErrorResponse
_WatcherCleared = _Error . hasCode 400

_EventIndexCleared :: Getting (First ErrorResponse) ResponseBody ErrorResponse
_EventIndexCleared = _Error . hasCode 401

hasCode :: (Choice p, Applicative f)
        => Word16
        -> Optic' p f ErrorResponse ErrorResponse
hasCode n = filtered ((n ==) . errorCode)


type Key   = Text
type Value = Text

data TTL = NoTTL | TTL !Word64
    deriving Show

instance QueryValueLike TTL where
    toQueryValue NoTTL   = Nothing
    toQueryValue (TTL n) = Just (toByteString' n)


get :: Monad m => Key -> KeysAPI m Response
get k = get' k getOptions

get' :: Monad m => Key -> GetOptions -> KeysAPI m Response
get' k = singleton . Get k . Right

set :: Monad m => Key -> Value -> Maybe TTL -> KeysAPI m Response
set k v ttl' = singleton . Put k $
    putOptions & lset pValue (Just v)
               & lset pTTL   ttl'

update :: Monad m => Key -> Maybe Value -> Maybe TTL -> KeysAPI m Response
update k v ttl' = singleton . Put k $
    putOptions & lset pValue     v
               & lset pTTL       ttl'
               & lset pPrevExist (Just True)

rm :: Monad m => Key -> KeysAPI m Response
rm k = singleton $ Delete k deleteOptions

rmr :: Monad m => Key -> KeysAPI m Response
rmr k = singleton $ Delete k (deleteOptions & lset dRecursive True)

mkdir :: Monad m => Key -> Maybe TTL -> KeysAPI m Response
mkdir k ttl' = singleton . Put k $
    putOptions & lset pDir True
               & lset pTTL ttl'

rmdir :: Monad m => Key -> KeysAPI m Response
rmdir k = singleton $ Delete k (deleteOptions & lset dDir True)

createInOrder :: Monad m => Key -> Maybe Value -> Maybe Word64 -> KeysAPI m Response
createInOrder k v ttl' = singleton . Post k $
    postOptions & lset cValue v
                & lset cTTL   ttl'

watch :: Monad m => Key -> Bool -> Maybe Word64 -> KeysAPI m Response
watch k recur after = singleton . Get k . Left $
    watchOptions & lset wRecursive recur . lset wAfterIndex after

-- | Continuously watch a given key
--
-- >>> watcher "foo" False Nothing $ \rs k -> lift (print rs) *> k
watcher
    :: Monad m
    => Key -> Bool -> Maybe Word64
    -> (Response -> KeysAPI m a -> KeysAPI m a)
    -> KeysAPI m a
watcher k r a f = do
    rs <- watch k r a
    f rs (watcher k r (Just (etcdIndex rs)) f)

refresh :: Monad m => Key -> Word64 -> KeysAPI m Response
refresh k ttl' = singleton . Put k $
    putOptions & lset pValue   Nothing
               & lset pTTL     (Just (TTL ttl'))
               & lset pRefresh True

casVal :: Monad m
       => Key
       -> Value             -- ^ expected value
       -> Maybe Value       -- ^ new value ('Nothing' removes the data)
       -> Maybe TTL         -- ^ new ttl   (optional)
       -> Maybe Word64      -- ^ expected index (optional)
       -> KeysAPI m Response
casVal k prev v ttl' idx = singleton . Put k $
    putOptions & lset pPrevValue (Just prev)
               & lset pValue     v
               & lset pTTL       ttl'
               & lset pPrevIndex idx

casIdx :: Monad m
       => Key
       -> Word64            -- ^ expected index
       -> Maybe Value       -- ^ new value ('Nothing' removes the data)
       -> Maybe TTL         -- ^ new ttl   (optional)
       -> Maybe Value       -- ^ expected value (optional)
       -> KeysAPI m Response
casIdx k idx v ttl' prev = singleton . Put k $
    putOptions & lset pPrevIndex (Just idx)
               & lset pValue     v
               & lset pTTL       ttl'
               & lset pPrevValue prev

cadVal :: Monad m
       => Key
       -> Value             -- ^ expected value
       -> Maybe Word64      -- ^ expected index (optional)
       -> KeysAPI m Response
cadVal k v idx = singleton . Delete k $
    deleteOptions & lset dPrevValue (Just v)
                  & lset dPrevIndex idx

cadIdx :: Monad m
       => Key
       -> Word64            -- ^ expected index
       -> Maybe Value       -- ^ expected value (optional)
       -> KeysAPI m Response
cadIdx k idx v = singleton . Delete k $
    deleteOptions & lset dPrevIndex (Just idx)
                  & lset dPrevValue v
