module Control.Monad.Etcd.Class where

import Control.Monad.Trans.Free
import Data.Etcd.Free


class (Functor m, Applicative m, Monad m) => MonadEtcd m where
    liftEtcd :: FreeT EtcdF m a -> m a
