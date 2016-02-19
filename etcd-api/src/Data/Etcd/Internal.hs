-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE Rank2Types       #-}

module Data.Etcd.Internal
    ( gParsePrefixed
    , stripFieldPrefix

    , Lens
    , Lens'
    , lens
    , lset

    , Prism
    , Prism'
    , prism

    , Optic
    , Optic'
    , filtered

    , Getting
    )
where

import Control.Applicative    (Const)
import Control.Monad.Identity (Identity (..))
import Data.Aeson.Types
import Data.Char
import Data.Profunctor
import GHC.Generics


gParsePrefixed :: (Generic a, GFromJSON (Rep a)) => Value -> Parser a
gParsePrefixed = genericParseJSON defaultOptions
    { fieldLabelModifier = stripFieldPrefix
    }

stripFieldPrefix :: String -> String
stripFieldPrefix s = case dropWhile isLower s of
    []     -> []
    (x:xs) -> toLower x : xs


--
-- Inevitable mini-lens
--

type Lens s t a b = forall f. Functor f => (a -> f b) -> s -> f t
type Lens' s a = Lens s s a a

lens :: (s -> a) -> (s -> b -> t) -> Lens s t a b
lens sa sbt afb s = sbt s <$> afb (sa s)
{-# INLINE lens #-}

lset :: Lens s t a b -> b -> s -> t
lset l a = runIdentity . l (Identity . const a)
{-# INLINE lset #-}


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
