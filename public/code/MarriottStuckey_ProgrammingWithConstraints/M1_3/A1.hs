{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module M1_3.A1 where

import           Control.Applicative
import           Control.Lens
import           Data.Foldable (Foldable, fold, foldMap)
import           Data.List
import           Data.Map (Map)
import qualified Data.Map as Map
import           Data.Monoid
import           Data.Set (Set)
import qualified Data.Set as Set
import           Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import           Test.QuickCheck

{-

## Pretty printing

-}

class Pr a where
  pr :: a -> Text

instance Pr Int     where pr = Text.pack . show
instance Pr Integer where pr = Text.pack . show

prIO :: Pr a => a -> IO ()
prIO = Text.putStrLn . pr

--------------------------------------------------------------------------------

{-

## Polynomial equations

Arithmetic constraints are defined as equations of polynomials. We'll
create a general description of polynomials as sums of free Abelian
groups on an index set.

-}

class Monoid m => Group m where
  inv :: m -> m

-- | Free Abelian group on a type of generators `v`.
newtype Ab v =
  Ab (Map v Int)
  deriving ( Eq, Ord, Show, Monoid )
makeWrapped ''Ab

normMap :: (Eq a, Num a) => Map v a -> Map v a
normMap = Map.filter (/= 0)

instance Pr v => Pr (Ab v) where
  pr = foldMap (\(v, i) -> pr v <> "[" <> pr i <> "]") . Map.toList . op Ab

instance (Ord v, Arbitrary v) => Arbitrary (Ab v) where
  arbitrary = Ab . normMap . Map.fromList <$> arbitrary

abMap :: Ord v' => (v -> v') -> (Ab v -> Ab v')
abMap f = _Wrapped %~ normMap . Map.mapKeysWith (+) f

abAp :: Ord v' => Ab (v -> v') -> (Ab v -> Ab v')
abAp af ax =
  flip abBind af $ \f ->
  flip abBind ax $ \x ->
  abInj (f x)

abInj :: v -> Ab v
abInj v = Ab (Map.singleton v 1)

abBind :: Ord v' => (v -> Ab v') -> (Ab v -> Ab v')
abBind f = _Wrapped . mapList %~ flatMap (Map.toList . op Ab . f) where
  flatMap :: (v -> [(v', Int)]) -> ([(v, Int)] -> [(v', Int)])
  flatMap f vi = vi >>= (\(v, i) -> map (over _2 (*i)) (f v))
  mapList :: (Num v', Eq v', Ord k') => Iso (Map k v) (Map k' v') [(k, v)] [(k', v')]
  mapList = iso Map.toList (normMap . Map.fromListWith (+))

abComp :: Ord c => (a -> Ab b) -> (b -> Ab c) -> (a -> Ab c)
abComp f g a = abBind g (f a)

abCoef :: Ab () -> Int
abCoef = maybe 0 id . preview (_Wrapped . ix ())

monomialDegree :: Ab v -> Int
monomialDegree = abCoef . abBind (const $ abInj ())

{-

## Gauss-Jordan Elimination (pp 21)

The Gauss-Jordan elimination algorithm has two sets of equations: C,
the unsolved equations and S, te solved form equations. At each step
the constraint C and S is equivalent to the initial constraint. The
algorithm works by repeatedly selecting an equation c from C. If c has
no variables it is tested for satisfiability. Otherwise, it can be
rewritten into the form x = e and used to eliminate x from the
remaining equations in C and S. The equation x = e is then added to S.

-}

--------------------------------------------------------------------------------

{-

First we need some notions of polynomial expressions in arbitrary
variables.

-}

-- class Monoid a => Grp a where
--   inv :: a -> a

-- newtype Abelian v = Abelian (Map v Int)              deriving ( Eq, Ord, Show )
-- newtype Poly  a v = Poly (Map (Maybe (Abelian v)) a) deriving ( Eq, Ord, Show )

-- abMap :: Ord v' => (v -> v') -> Abelian v -> Abelian v'
-- abMap f (Abelian m) = Abelian (Map.mapKeysWith (+) f m)

-- instance Pointed Abelian where
--   point = Abelian . flip Map.singleton 1

-- abBind :: Ord v' => (v -> Abelian v') -> Abelian v -> Abelian v'
-- abBind f (Abelian m) =
--   Abelian . simpl . Map.fromListWith (+) $ flat =<< Map.toList m where
--     flat (v, a) = let Abelian m = f v in map (\(v', a') -> (v', a * a')) (Map.toList m)

-- instance Ord v => Monoid (Abelian v) where
--   mempty = Abelian mempty
--   Abelian a `mappend` Abelian b = Abelian (Map.unionWith (+) a b)

-- instance Ord v => Grp (Abelian v) where
--   inv (Abelian a) = Abelian (fmap negate a)

-- simpl :: (Eq v, Num v) => Map k v -> Map k v
-- simpl = Map.filter (/= 0)

-- instance (Ord v, Num a) => Num (Poly a v) where
--   Poly a + Poly b = Poly (Map.unionWith (+) a b)
--   Poly a * Poly b = Poly . Map.fromList $ do
--     (ag, av) <- Map.toList a
--     (bg, bv) <- Map.toList b
--     return (ag <> bg, av * bv)
--   abs    = error "Poly has no abs"
--   signum = error "Poly has no signum"
--   fromInteger i | i == 0    = Poly mempty
--                 | otherwise = Poly (Map.singleton Nothing (fromInteger i))
--   negate (Poly a) = Poly (fmap negate a)

-- instance Num a => Pointed (Poly a) where
--   point v = Poly (Map.singleton (Just (point v)) 1)

-- -- data Equation       v a = (:==) (Poly v a) (Poly v a)

-- -- -- | Enforce that the left side cannot appear in the variables in the right side
-- -- data SolvedEquation v a = (:=) v (Poly v a)

-- -- solve :: Equation v a -> Maybe (SolvedEquation v a)
-- -- solve = 