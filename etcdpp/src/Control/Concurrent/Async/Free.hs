{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts          #-}
{-# LANGUAGE MultiParamTypeClasses     #-}
{-# LANGUAGE OverloadedStrings         #-}
{-# LANGUAGE PartialTypeSignatures     #-}

module Control.Concurrent.Async.Free where

import qualified Control.Concurrent.Async        as Async
import qualified Control.Concurrent.Async.Lifted as AsyncL
import           Control.Monad.Etcd.Class
import           Control.Monad.Trans.Free
import           Data.Etcd.Free
import           Data.Void


data RaceF m next
    = forall a b. Race (m a) (m b) (Either a b -> next)

instance Functor (RaceF m) where
    fmap f (Race ma mb next) = Race ma mb (f <$> next)

race :: MonadFree (RaceF n) m => n a -> n b -> m (Either a b)
race a b = liftF $ Race a b id

raceIO :: RaceF IO (IO a) -> IO a
raceIO (Race ma mb next) = Async.race ma mb >>= next

--raceEtcd :: RaceF (FreeT EtcdF m)
raceEtcd (Race ma mb next) = AsyncL.race (liftEtcd ma) (liftEtcd mb) >>= next

--while :: (Monad m, Monad n) => n Void -> n a -> FreeT (RaceF n) m a
while :: MonadFree (RaceF n) m => n Void -> n a -> m a
while v a = either absurd id <$> race v a


program :: MonadFree (RaceF IO) IO => IO (Either () ())
program = race (putStrLn "a") (putStrLn "b")

program1 :: Monad m => FreeT (RaceF (FreeT EtcdF m)) m (Either Response Response)
--program1 :: (MonadFree (RaceF (FreeT EtcdF m)) n, Monad m) => n (Either Response Response)
program1 = race (getKey "a" getOptions) (getKey "b" getOptions)
