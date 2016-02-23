-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE Rank2Types #-}

module Data.Etcd.Lens
    ( -- * 'GetOptions'
      gRecursive
    , gSorted
    , gQuorum

      -- * 'PutOptions'
    , pValue
    , pTTL
    , pPrevValue
    , pPrevIndex
    , pPrevExist
    , pRefresh
    , pDir

      -- * 'PostOptions'
    , cValue
    , cTTL

      -- * 'DeleteOptions'
    , dRecursive
    , dPrevValue
    , dPrevIndex
    , dDir

      -- * 'WatchOptions'
    , wRecursive
    , wWaitIndex

      -- * Response Prisms
    , _Error
    , _Success

      -- ** Matching Error Codes
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
    )
where

import Control.Applicative (Const)
import Data.Etcd.Types
import Data.Monoid         (First)
import Data.Profunctor     (Choice, dimap, right')
import Data.Text           (Text)
import Data.Word           (Word16, Word64)


gRecursive :: Lens' GetOptions Bool
gRecursive = lens _gRecursive (\s a -> s { _gRecursive = a })

gSorted :: Lens' GetOptions Bool
gSorted = lens _gSorted (\s a -> s { _gSorted = a })

gQuorum :: Lens' GetOptions Bool
gQuorum = lens _gQuorum (\s a -> s { _gQuorum = a })


pValue :: Lens' PutOptions (Maybe Value)
pValue = lens _pValue (\s a -> s { _pValue = a })

pTTL :: Lens' PutOptions (Maybe SetTTL)
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


cValue :: Lens' PostOptions (Maybe Text)
cValue = lens _cValue (\s a -> s { _cValue = a })

cTTL :: Lens' PostOptions (Maybe Word64)
cTTL = lens _cTTL (\s a -> s { _cTTL = a })


dRecursive :: Lens' DeleteOptions Bool
dRecursive = lens _dRecursive (\s a -> s { _dRecursive = a })

dPrevValue :: Lens' DeleteOptions (Maybe Value)
dPrevValue = lens _dPrevValue (\s a -> s { _dPrevValue = a })

dPrevIndex :: Lens' DeleteOptions (Maybe Word64)
dPrevIndex = lens _dPrevIndex (\s a -> s { _dPrevIndex = a })

dDir :: Lens' DeleteOptions Bool
dDir = lens _dDir (\s a -> s { _dDir = a })


wRecursive :: Lens' WatchOptions Bool
wRecursive = lens _wRecursive (\s a -> s { _wRecursive = a })

wWaitIndex :: Lens' WatchOptions (Maybe Word64)
wWaitIndex = lens _wWaitIndex (\s a -> s { _wWaitIndex = a })


_Success :: Prism' ResponseBody SuccessResponse
_Success = prism Success $ \case
    Success r -> Right r
    x         -> Left  x

_Error :: Prism' ResponseBody ErrorResponse
_Error = prism Error $ \case
    Error r -> Right r
    x       -> Left  x


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

hasCode
    :: ( Choice      p
       , Applicative f
       )
    => Word16
    -> Optic' p f ErrorResponse ErrorResponse
hasCode n = filtered ((n ==) . errorCode)


--
-- Inevitable mini-lens
--

type Lens s t a b = forall f. Functor f => (a -> f b) -> s -> f t
type Lens' s a = Lens s s a a

lens :: (s -> a) -> (s -> b -> t) -> Lens s t a b
lens sa sbt afb s = sbt s <$> afb (sa s)
{-# INLINE lens #-}


type Prism s t a b = forall p f. (Choice p, Applicative f) => p a (f b) -> p s (f t)
type Prism' s a = Prism s s a a

prism :: (b -> t) -> (s -> Either t a) -> Prism s t a b
prism bt seta = dimap seta (either pure (fmap bt)) . right'
{-# INLINE prism #-}


type Optic p f s t a b = p a (f b) -> p s (f t)
type Optic' p f s a = Optic p f s s a a

filtered :: (Choice p, Applicative f) => (a -> Bool) -> Optic' p f a a
filtered p = dimap (\x -> if p x then Right x else Left x) (either pure id) . right'
{-# INLINE filtered #-}


type Getting r s a = (a -> Const r a) -> s -> Const r s
