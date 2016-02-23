-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE UndecidableInstances       #-}

module Control.Monad.Trans.Etcd
    ( EtcdT
    , runEtcdT
    , module Data.Etcd.Free
    )
where

import Control.Applicative
import Control.Monad
import Control.Monad.Base
import Control.Monad.Catch
import Control.Monad.IO.Class
import Control.Monad.Trans.Class
import Control.Monad.Trans.Control
import Control.Monad.Trans.Free        (FreeF (Pure), FreeT (..))
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

instance MonadBase b m => MonadBase b (EtcdT m) where
    liftBase = liftBaseDefault

instance MonadBaseControl b m => MonadBaseControl b (EtcdT m) where
    type StM (EtcdT m) a = StM m (FreeF EtcdF a (FreeT EtcdF m a))

    liftBaseWith f = EtcdT . toFT . FreeT . fmap Pure $
        liftBaseWith $ \runInBase ->
            f $ \k ->
                runInBase $
                    runFreeT (fromFT (unEtcdT k))

    restoreM = EtcdT . toFT . FreeT . restoreM


runEtcdT :: MonadCatch m => (EtcdF (m a) -> m a) -> EtcdT m a -> m a
runEtcdT f (EtcdT m) = iterT f m
