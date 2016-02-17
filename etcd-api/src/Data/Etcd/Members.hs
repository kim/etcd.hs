-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GADTs         #-}

module Data.Etcd.Members
    ( MembersAPI
    , MembersF   (..)
    , Members    (members)
    , Member     (..)
    , URL        (..)
    , PeerURLs   (..)

    , listMembers
    , addMember
    , deleteMember
    , updateMember
    )
where

import Control.Monad.Operational
import Data.Aeson.Types
import Data.Etcd.Internal
import Data.Text                 (Text)
import GHC.Generics


type MembersAPI = ProgramT MembersF

data MembersF a where
    ListMembers  ::                         MembersF Members
    AddMember    :: PeerURLs             -> MembersF Member
    DeleteMember :: MemberId             -> MembersF ()
    UpdateMember :: MemberId -> PeerURLs -> MembersF ()


listMembers :: Monad m => MembersAPI m Members
listMembers = singleton ListMembers

addMember :: Monad m => PeerURLs -> MembersAPI m Member
addMember = singleton . AddMember

deleteMember :: Monad m => MemberId -> MembersAPI m ()
deleteMember = singleton . DeleteMember

updateMember :: Monad m => MemberId -> PeerURLs -> MembersAPI m ()
updateMember m = singleton . UpdateMember m


newtype Members = Members { members :: [Member] }
    deriving (Show, Generic)

instance FromJSON Members


type MemberId = Text


data Member = Member
    { mId         :: Maybe MemberId
    , mName       :: Maybe Text
    , mPeerURLs   :: [URL]
    , mClientURLs :: Maybe [URL]
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
