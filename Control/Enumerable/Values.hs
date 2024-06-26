{-#LANGUAGE DeriveDataTypeable#-}
module Control.Enumerable.Values
  ( values
  , values'
  , allValues
  , Values (..)
  )  where

import Control.Enumerable

-- | Constructs all values of a given size.
values :: Enumerable a => Int -> [a]
values = runValues global

-- | Constructs all values up to a given size.
values' :: Enumerable a => Int -> [[a]]
values' i = let f = runValues global in [f x|x <- [0..i]]

allValues :: Enumerable a => [[a]]
allValues = aux global global where
  aux :: Values a -> MaxSize a -> [[a]]
  aux (Values f) (MaxSize m) = map f (zipWith const [0..] m)



newtype Values a = Values {runValues :: Int -> [a]} deriving Typeable

instance Functor Values where
  fmap f = Values . fmap (fmap f) . runValues

instance Applicative Values where
  pure x     = Values $ \i -> if i == 0 then [x] else []
  fs <*> xs  = fmap (uncurry ($)) (pair fs xs)

instance Alternative Values where
  empty     = Values $ \_ -> []
  xs <|> ys = Values $ \i -> runValues xs i ++ runValues ys i

instance Sized Values where
  pay xs       = Values $ \i -> if i > 0 then runValues xs (i-1) else []
  pair xs ys   = Values $ \i -> [(x,y)|n <- [0..i], x <- runValues xs n, y <- runValues ys (i-n)]

  fin n        = Values $ \i -> if i == 0 then [0..n-1] else []
  aconcat []   = empty
  aconcat [x]  = x
  aconcat xss  = Values $ \i -> concatMap (($ i) . runValues) xss




-- Useful for detecting if an enumeration is finite.
data MaxSize a = MaxSize {runMaxSize :: [()]} deriving (Show, Typeable)
instance Functor MaxSize where fmap _ = MaxSize . runMaxSize

instance Applicative MaxSize where
  pure _ = MaxSize [()]
  MaxSize [] <*> _  = empty
  _ <*> MaxSize []  = empty
  f <*> x = MaxSize $ drop 1 (runMaxSize f ++ runMaxSize x)

instance Alternative MaxSize where
  empty = MaxSize []
  a <|> b = MaxSize (runMaxSize a `zipL` runMaxSize b) where
    zipL [] x = x
    zipL x [] = x
    zipL (_:xs) (_:ys) = () : xs `zipL` ys


instance Sized MaxSize where
  pay = MaxSize . (():) . runMaxSize


type TT = Bool --  [[[[[[[[[[Bool]]]]]]]]]]
tst1 n = take n $ runMaxSize (local :: MaxSize TT)

