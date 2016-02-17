-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE Rank2Types       #-}

module Data.Etcd.Internal
    ( gParsePrefixed
    , stripFieldPrefix
    )
where

import Data.Aeson.Types
import Data.Char
import GHC.Generics


gParsePrefixed :: (Generic a, GFromJSON (Rep a)) => Value -> Parser a
gParsePrefixed = genericParseJSON defaultOptions
    { fieldLabelModifier = stripFieldPrefix
    }

stripFieldPrefix :: String -> String
stripFieldPrefix s = case dropWhile isLower s of
    []     -> []
    (x:xs) -> toLower x : xs
