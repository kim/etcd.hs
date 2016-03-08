-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

module Data.Etcd.Recipes.Internal
    ( Min (..)
    , Max (..)
    )
where


newtype Max a = Max { getMax :: Maybe a }
newtype Min a = Min { getMin :: Maybe a }

instance Ord a => Monoid (Max a) where
    mempty = Max Nothing

    {-# INLINE mappend #-}
    m `mappend` Max Nothing = m
    Max Nothing `mappend` n = n
    (Max m@(Just x)) `mappend` (Max n@(Just y))
      | x >= y    = Max m
      | otherwise = Max n

instance Ord a => Monoid (Min a) where
  mempty = Min Nothing

  {-# INLINE mappend #-}
  m `mappend` Min Nothing = m
  Min Nothing `mappend` n = n
  (Min m@(Just x)) `mappend` (Min n@(Just y))
    | x <= y    = Min m
    | otherwise = Min n
