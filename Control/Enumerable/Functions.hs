{-#LANGUAGE GADTs, TypeOperators, DeriveDataTypeable, DeriveFunctor, StandaloneDeriving #-}

module Control.Enumerable.Functions where

import Control.Sized
import Control.Enumerable
import Control.Enumerable.Values
import Control.Enumerable.Count

import Control.Monad(msum)
import Data.List(intercalate)
import Data.Either(partitionEithers)

-- | Type alias for avoiding TypeOperators.
type Function a b = a :-> b

-- | Functions from a to b
data a :-> b where
  Constant    :: b -> (a :-> b)
  Case        :: [Pattern a b] -> (a :-> b)
  Uncurry     :: (a :-> (b :-> c)) -> ((a,b) :-> c)
  deriving (Typeable)

-- | Case alternatives matching on values of type a, mapping to values of type b
data Pattern a b where
  Pattern :: (String,Int) -> (a -> Maybe x) -> (x :-> b) -> Pattern a b
  NilPat  :: String -> (a -> Bool) -> b -> Pattern a b
  deriving (Typeable)

deriving instance Functor ((:->) a)
deriving instance Functor (Pattern a)

rhss :: (a :-> b) -> [b]
rhss (Constant x) = [x]
rhss (Case ps)    = concatMap rhsPattern ps
rhss (Uncurry f)  = concatMap rhss (rhss f)

rhsPattern :: Pattern a b -> [b]
rhsPattern (Pattern _ _ f)     = rhss f
rhsPattern (NilPat _ _ x)  = [x] 

-- Is this function minimal in the sense that it has no "false" case distinctions (yielding the same value for all cases)
mini :: Eq b => Function a b -> Bool
mini = either (const True) id . miniF

miniF :: Eq b => Function a b -> Either b Bool
miniF (Constant x) = Left x
miniF (Case ps)    = miniP ps
miniF (Uncurry f)  = resolve $ map miniF $ rhss f

miniP :: Eq b => [Pattern a b] -> Either b Bool
miniP ps = resolve (map minP ps)
  where  minP :: Eq b => Pattern a b -> Either b Bool
         minP (NilPat _ _ x)   = Left x
         minP (Pattern _ _ f)  = miniF f

resolve :: Eq b => [Either b Bool] -> Either b Bool
resolve ebs = case bs of
  [] -> case xs of  -- There are only leafs
    [x]    -> Left x
    (x:xs) -> Right $ not $ all (x ==) xs
  _  -> Right (and bs) -- All subpatterns are minimal
  where  (xs,bs) = partitionEithers ebs


instance Show b => Show (a :-> b) where
  show (Constant a) = "\\_ -> " ++ show a
  show (Case ps)   = unlines $ 
     ["\\x -> case x of "
     ] ++ map ("  "++) (concatMap (lines . show) ps)
--  show (Uncurry (Constant (Constant f))) = "\\(_,_) -> " ++ show f 
  show (Uncurry f) = "uncurry (" ++ show f ++ "  )"

instance Show b => Show (Pattern a b) where
  show (Pattern (s,k) _ f) =   unwords (s:take k names) 
                           ++  " -> (" ++ show f ++ "  ) " 
                           ++  stuple (take k names)
  show (NilPat s _ f)  = s ++  " -> " ++ show f

stuple [s] = s
stuple (s:ss) = "("++s++","++stuple ss++")"
names = ['x':show n|n<-[1..]]

-- | Function application
($$) :: (a :-> b) -> a -> b
Constant a $$ b     = a
Case ps $$ b        = maybe (error "Incomplete pattern") id $ msum [match p b | p <- ps]
Uncurry f $$ (a,b)  = f $$ a $$ b

match :: (Pattern a b) -> a -> Maybe b
match (Pattern _ p f) = fmap (f $$) . p
match (NilPat _ p f)  = \a -> if p a then Just f else Nothing

instance (Enumerable b, Parameter a) => Enumerable (a :-> b) where
  enumerate = functions




-- | A class of types that can be used as parameters to enumerable functions
class Typeable a => Parameter a where
  functions :: (Enumerable b, Typeable f, Sized f) => Shared f (a :-> b)


signature :: (Typeable a, Enumerable x, Enumerable b, Typeable f, Sized f) 
               => (x -> [Pattern a b]) -> Shared f (a :-> b)
signature f = share (fmap Constant access <|> pay ps) 
  where ps = fmap (Case . f) access -- :: f [Pattern a b]

showPat :: (Eq a, Show a) => a -> b -> Pattern a b
showPat a b = NilPat (show a) (==a) b

instance Parameter () where
  functions = share $ fmap Constant access -- Avoid pattern matching on ()

instance (Parameter a, Parameter b) => Parameter (a,b) where
  functions = share $ fmap Uncurry access

instance (Parameter a, Parameter b) => Parameter (Either a b) where
  functions = signature go
    where go (f,g) = [p1 "Left" extL f, p1 "Right" extR g]
          extL = either Just (const Nothing)
          extR = either (const Nothing) Just


instance Parameter Bool where
  functions = signature go
    where go (f,g) = [showPat False f, showPat True g]

instance Parameter a => Parameter [a] where
  functions = signature go
    where go (f,g) = [p0 "[]" null f, p2 "(:)" extCons g]
          extCons xs = do h:t <- return xs ; return (h,t) -- Nicer way to write patterns? LC + listToMaybe?
                     -- listToMaybe [(h,t)|let h:t = xs]


p0 :: String -> (a -> Bool) -> b -> Pattern a b
p0 s f b = NilPat s f b

p1 :: String -> (a -> Maybe x1) -> (x1 :-> b) -> Pattern a b
p1 s = Pattern (s,1)

p2 :: String -> (a -> Maybe (x1,x2)) -> ((x1,x2) :-> b) -> Pattern a b
p2 s = Pattern (s,2)

p3 :: String -> (a -> Maybe (x1,x2,x3)) -> ((x1,x2,x3) :-> b) -> Pattern a b
p3 s = Pattern (s,3)

-- ...

