-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

module Control.Monad.Trans.Etcd
    ( EtcdT
    , runEtcdT
    )
where

import Control.Monad.Trans.Free.Church
import Data.Etcd.Free                  (EtcdF)


type EtcdT = FT EtcdF

runEtcdT :: Monad m => (EtcdF (m a) -> m a) -> EtcdT m a -> m a
runEtcdT = iterT
