module WFF (
    BMap(..),
    UnaryOp,
    makeUnary,
    BinaryOp,
    makeBinary,
    WFF(..),
    render,
    eval,
    negOp,
    andOp,
    orOp,
    impliesOp,
    match
) where

import Prelude
    ( class Eq, class Ord, class Functor, class Apply, class Applicative
    , class Bind, class Monad
    , not
    , (<>), ($), (<$>), (<*>), (>>=), (<<<), (==), (&&), (||), (<=))
import Data.Foldable (class Foldable, foldMap, foldlDefault, foldrDefault)
import Data.Traversable (class Traversable, sequence, traverseDefault)
import Data.Map as M

import Mapping (Mapping(..))

data BMap a = BMap (Boolean -> a)

applyBMap :: forall a. BMap a -> Boolean -> a
applyBMap (BMap f) = f

instance eqBoolFunction :: Eq a => Eq (BMap a) where
    eq (BMap f) (BMap g) = f true == g true && f false == g false

type UnaryOp =
    { function :: BMap Boolean
    , symbol :: String
    }

makeUnary :: (Boolean -> Boolean) -> String -> UnaryOp
makeUnary f symbol =
    { function : BMap f
    , symbol
    }

type BinaryOp =
    { function :: BMap (BMap Boolean)
    , symbol :: String
    }

makeBinary :: (Boolean -> Boolean -> Boolean) -> String -> BinaryOp
makeBinary f symbol =
    { function : BMap (\x -> BMap (f x))
    , symbol
    }

data WFF a
    = Prop a
    | Unary { operator :: UnaryOp, contents :: WFF a }
    | Binary { operator :: BinaryOp, left :: WFF a, right :: WFF a }

derive instance eqWFF :: Eq a => Eq (WFF a)

instance functorWFF :: Functor WFF where
    map f (Prop p) = Prop $ f p
    map f (Unary u) = Unary $ u { contents = f <$> u.contents }
    map f (Binary b) =
        Binary $ b { left = f <$> b.left, right = f <$> b.right}

instance applyWFF :: Apply WFF where
    apply (Prop f) w = f <$> w
    apply (Unary u) w = Unary $ u { contents = u.contents <*> w }
    apply (Binary b) w =
        Binary $ b { left = b.left <*> w, right = b.right <*> w }

instance applicativeWFF :: Applicative WFF where
    pure = Prop

instance bindWFF :: Bind WFF where
    bind (Prop p) f = f p
    bind (Unary u) f = Unary $ u { contents = u.contents >>= f }
    bind (Binary b) f =
        Binary $ b { left = b.left >>= f, right = b.right >>= f}

instance monadWFF :: Monad WFF

instance foldableWFF :: Foldable WFF where
    foldMap f (Prop p) = f p
    foldMap f (Unary u) = foldMap f u.contents
    foldMap f (Binary b) = foldMap f b.left <> foldMap f b.right
    foldl f x y = foldlDefault f x y
    foldr f x y = foldrDefault f x y

instance traversableWFF :: Traversable WFF where
    sequence (Prop p) = Prop <$> p
    sequence (Unary u) = Unary <<< u { contents = _ } <$> sequence u.contents
    sequence (Binary b) = Binary <$> (b { left = _, right = _}
        <$> sequence b.left
        <*> sequence b.right)
    traverse = traverseDefault

-- Render a WFF to show to the user
render :: WFF String -> String
render (Prop p) = p
render (Unary u) = u.operator.symbol <> safeRender u.contents
render (Binary b) = safeRender b.left <> b.operator.symbol <> safeRender b.right

-- Renders a WFF to be contained in another WFF
safeRender :: WFF String -> String
safeRender (Prop p) = p
safeRender w = "(" <> render w <> ")"

-- Evaluate a WFF
eval :: WFF Boolean -> Boolean
eval (Prop p) = p
eval (Unary u) = applyBMap u.operator.function $ eval u.contents
eval (Binary b) =
    applyBMap (applyBMap b.operator.function $ eval b.left) $ eval b.right

negOp :: UnaryOp
negOp = makeUnary not "~"

andOp :: BinaryOp
andOp = makeBinary (&&) "&"

orOp :: BinaryOp
orOp = makeBinary (||) "|"

impliesOp :: BinaryOp
impliesOp = makeBinary (<=) "->"

-- Match a WFF to one after substitutions were applied, returning the relevant
-- substitutions
match :: forall x y. Ord x => Eq y => WFF x -> WFF y -> Mapping x (WFF y)
match (Prop p) w = Mapping $ M.singleton p w
match (Unary u) (Unary v)
    | u.operator == v.operator = match u.contents v.contents
match (Binary b) (Binary c)
    | b.operator == c.operator = match b.left c.left <> match b.right c.right
match _ _ = None
