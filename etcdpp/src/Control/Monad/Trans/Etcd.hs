-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE UndecidableInstances       #-}

module Control.Monad.Trans.Etcd
    ( EtcdT    (..)
    , runEtcdT
    )
where

import Control.Applicative
import Control.Monad
import Control.Monad.Catch
import Control.Monad.IO.Class
import Control.Monad.Trans.Class
import Control.Monad.Trans.Free.Church
import Data.Etcd.Free


newtype EtcdT m a = EtcdT { unEtcdT :: FT EtcdF m a }
    deriving ( Functor
             , Applicative
             , Alternative
             , Monad
             , MonadFree EtcdF
             , MonadIO
             , MonadPlus
             , MonadTrans
             , MonadThrow
             , MonadCatch
             )

runEtcdT :: MonadCatch m => (EtcdF (m a) -> m a) -> EtcdT m a -> m a
runEtcdT f (EtcdT m) = iterT f m
