---
layout: post
title: Mutable Algorithms in Immutable Languages, Part 3
---

*Or: a love song to rank-2 types and phantom variables.*

*See also [part 1][part 1] and [part 2][part 2]. All of the code in
 this post [is available in the blog repository on Github][repo].*

In [part 1][part 1] we demonstrated that we can write algorithms which
require mutable references by embedding them in an abstract monad,
which I called `Mem`, that is adequate to describe a sequential
process of creating, reading, and writing from mutable references. In
[part 2][part 2] we instantiated this monad twice, first impurely and
then later purely, and showed that these implementations sufficiently
modeled the interface allowing our mutable algorithms to be executed.

But we also saw a flaw in the pure approach. The API allows us to
build computations which may fail violate our expectations for how
mutable references work---it's easy to construct "valid looking" uses
which throw errors or behave unexpectedly.

I called the exposed flaw a "border crossing bug". Subtly, one might
have noticed that this bug could not arise in the impure, `IO`-based
implementation. If you didn't notice that, then I encourage you to try
replicating the buggy code that used `UfIntMap` using `UfIO`.

What I'd like to suggest is that this bug demonstrates the tension
between pure and impure computations.

In this part I plan not only to resolve the bug by leaning on
Haskell's type system, but also to explore what it demonstrates, to
determine what exactly mutable algorithms demand from a language, and,
finally, to show how my fancily-typed solution and its cousin,
Haskell's `ST` monad, provide an adequate foundation for mutation.

* http://galois.squarespace.com/storage/files/downloads/publications-jl/lazy-functional-state-threads.pdf

## The unstable state of things

So let's really dive into this bug. Replicated from before:

~~~
bug =
  let
    n1 = runUfIntMap $ do
      node ()
      node ()
      node ()
    conn = runUfIntMap $ do
      n2 <- node ()
      connected n1 n2
  in
   conn
~~~
{: .language-haskell}

You might have argued that this is an obviously improper use of the
API afforded by `Mem` and `runUfIntMap`. In particular, each time
`runUfIntMap` is called the computation, its argument, is "run" in a
completely fresh environment. References from other environments are
not allowed as they do not have any meaning in a fresh environment.

Another way to examine the flaw here is to notice that there are two
complementary violations occurring. First, in the block named by `n1`
we allow a reference to "escape" its region of meaning by returning
it. Then, in the block named `conn` we run a computation which depends
upon a "foreign" reference which was imported from the surrounding
environment. Since we know how `runUfIntMap` works it's patently clear
to us that neither of those moves could possibly be
meaningful---again, references *only* make sense within the region
between the time a fresh `IntMap` environment is introduced and when
we extract the final result using `evalState`. In other words, the
region defined as the *argument* to `runUfIntMap`.

So let's just document the thing!

~~~
-- | 'Mem' monads allow for the creation and manipulation of mutable
--   references. The use of a reference, reading or writing is valid
--   iff it was created in the same thread. References which escape a
--   'Mem' computation are no longer guaranteed to be meaningful.
--   References imported into a 'Mem' computation will invariably lead
--   to errors or undefined behavior.
class (Monad r, Eq (Ref r)) => Mem r where ...
~~~
{: .language-haskell}

Actually, no, that's terrifically unsatisfying. We're not programming in a
pure, immutable langauge so that we have to deal with ambiguous
notions of "undefined behavior". If it's okay by you, I'll go
implement my Union/Find in C, thankyouverymuch.

## Eliminating bad computations

We'd like to eliminate the ability to write invalid computations of
the forms explored above *statically*. In other words, we need to find
a way to reflect that information in the types of our computations.

If it's not exactly obvious how to achieve that, don't worry. I'll
explore the solution in stages.

### A thread of their own

First, we'd like to begin to track the notion of how two `Mem`
computations which are sequenced together are now *linked* as
belonging to the same region. With this notion we'll maybe be able to
start talking about when two computations are not linked and how they
should not share information.

To do this, we'll add a new type variable to our `UfIntMap`
implementation: a *phantom* type variable just like `v`.
Traditionally, this is called `s` and it's almost an entirely trivial
change. The updated code is below and [here's a diff][the-diff]
showing the changed lines and emphasizing how trivial it is.

~~~
data Uf s v =
  Uf { count :: Int
     , mem   :: IntMap (Node_ (UfIntMap s v) v)
     }

uf0 :: Uf s v
uf0 = ...

newtype UfIntMap s v a =
  UfIntMap { unUfIntMap :: State (Uf s v) a }
  deriving ( Functor, Applicative, Monad )

runUfIntMap :: UfIntMap s v a -> a
runUfIntMap = ...

instance Mem (UfIntMap s v) where
  newtype Ref (UfIntMap s v) = UfIntMapRef { getId :: Int } deriving ( Eq )
  type    Val (UfIntMap s v) = Node_ (UfIntMap s v) v
  ...
~~~
{: .language-haskell}

[the-diff]:https://github.com/tel/tel.github.io/commit/5454c82aa12b1a6b8859f5bed4359175eb6cf664

In particular, we don't have to change the implementations of `ref`,
`deref`, or `set` at all. Even any properly running example programs
will continue to work so long as we update their type annotations.

~~~
exPure :: Bool
exPure = runUfIntMap computation where
  computation = do
    n1 <- node 1
    n2 <- node 2
    link n1 n2
    connected n1 n2
~~~
{: .language-haskell}

This is the beauty of phantom type information---it does nothing more
than provide additional information about computations we're already
able to do. The next step will be to refine what we consider *valid*
programs to be using this information, but for now let's see what
exactly we have wrought.

### Computations of a variable, uh, stick together

Let's consider the new types of things like `ref` and `deref` when
they're specified to `UfIntMap`:

~~~
ref   :: Val (UfIntMap s v) -> UfIntMap s v (Ref (UfIntMap s v))
deref :: Ref (UfIntMap s v) -> UfIntMap s v (Val (UfIntMap s v))
set   :: Ref (UfIntMap s v) ->
         Val (UfIntMap s v) ->
         UfIntMap s v ()
~~~
{: .language-haskell}

If you peer through some of the noise of expanding these definitions
you might notice something important---the phantom variable `s` is
*shared* from argument to result in every function. In other words,
calling `deref` on a `Ref` which is stated to occur in some *stateful
thread* named by `s` will return a `Val` in that *same* thread. There
would be a possibility for the phantom variables to differ, but
instead they are *unified* or *equivalated*.

We can do the same analysis for some other glue functions like monadic
`(>>=)`

~~~
(>>=) :: UfIntMap s v a -> (a -> UfIntMap s v b) -> UfIntMap s v b
(>>)  :: UfIntMap s v a ->       UfIntMap s v b  -> UfIntMap s v b
~~~
{: .language-haskell}

Again, the phantom variable seems to properly capture the notion that
computations which get threaded together must now, forever, share the
same `s`-variable. They must now, forever, live together in the same
stateful thread.

As a final example of this property, we can run a few experiments and
try to trick the compiler. For instance, let's make a concrete
`StateThread1` type and a function which `infects` computations with
that concrete thread type.

~~~
data StateThread1

infect1 :: UfIntMap StateThread1 Int ()
infect1 = return ()

exPure :: Bool
exPure = runUfIntMap computation where
  computation = do
    n1 <- node 1
    n2 <- node 2
    link n1 n2
    infect1            -- infected!
    connected n1 n2
~~~
{: .language-haskell}

This will run just fine

~~~
>>> exPure
True
~~~

but if we do the same with a new, definitely different `StateThread2` type

~~~
data StateThread2

infect2 :: UfIntMap StateThread2 Int ()
infect2 = return ()

exPure :: Bool
exPure = runUfIntMap computation where
  computation = do
    n1 <- node 1
    n2 <- node 2
    link n1 n2
    infect1
    infect2
    connected n1 n2
~~~
{: .language-haskell}

Then we get an error describing the exact problem.

~~~
UnionFind/IntMap.hs:67:5: Couldn't match type ‘StateThread2’ with ‘StateThread1’ …
    Expected type: UfIntMap StateThread1 Int ()
      Actual type: UfIntMap StateThread2 Int ()
    In a stmt of a 'do' block: infect2
    In the expression:
      do { n1 <- node 1;
           n2 <- node 2;
           link n1 n2;
           infect1;
           .... }
~~~

Perfect!

### Refining the types of a program

So far, while we've introduced these `s` variables and demonstrated
that they have a "stickiness" property that appears to reflect their
meaning as naming the "stateful thread" a computation lives within...
well, they don't seem to do much.

In particular, while we demand that sequencing unifies the stateful
threads we still accept every bad program as we did before because, so
long as we don't deliberately restrict the choice of that `s` variable
such as demonstrated using `StateThread1` and `StateThread2` together,
there's nothing that keeps Haskell from just unifying *every* `s`
variable together and calling it a day.

We need to find a way to tell Haskell that it is *not allowed* to
unify state threads across `runUfIntMap` boundaries. In particular,
we'd only like Haskell to accept as valid `UfIntMap` computations
where every `s`-marked type is both created and eliminated within the
same region. This is sufficient to disallow importing or exporting
references.

#### Universal Quantification

I'll jump to the solution and then try to justify it. What we need to
do is introduce what's known as a `RankNType` on the `runUfIntMap`
function. Interestingly, this is a one-line change which affects only
the type of `runUfIntMap` [^uhoh]

~~~
runUfIntMap :: (forall s. UfIntMap s v a) -> a
runUfIntMap comp = evalState (unUfIntMap comp) uf0
~~~
{: .language-haskell}

This one word change is all it takes to ensure that Haskell is extra
picky about the kinds of `UfIntMap` computations which are *allowed*
to be run. In particular, they must be entirely agnostic to the choice
of `s` variable preventing two things.

1. They can't depend upon outside types containing `s`-thread
   variables as these might be maliciously *fixed* while `runUfIntMap`
   only works for computations which are valid for *all* choices of
   `s`
2. They can't export types containing `s`-thread variables as then
   they could unify with `s`-variables in other computations meaning
   that the argument to `runUfIntMap` would no longer be truly
   universal in choice of `s`.

It's remarkable how this little change is *exactly* what we sought
out. It's a firm denial of programs which abuse imports or exports of
`s`-marked types. Our buggy programs from the previous post is
thoroughly outlawed:

~~~
exportBug =
  runUfIntMap $ do
    node ()
~~~
{: .langauge-haskell}

~~~
UnionFind/IntMap.hs:61:5: Couldn't match type ‘a’ with ‘Node (UfIntMap s ())’ …
      because type variable ‘s’ would escape its scope
~~~

~~~
importBug :: Node (UfIntMap s ()) -> Bool
importBug n1 =
  runUfIntMap $ do
    n2 <- node ()
    t <- connected n1 n2
    return t
~~~
{: .language-haskell}

~~~
UnionFind/IntMap.hs:64:20: Couldn't match type ‘s’ with ‘s1’ …
      ‘s’ is a rigid type variable bound by
          the type signature for importBug :: Node (UfIntMap s ()) -> Bool
          at /Users/tel/blog/public/code/MutableImmutable/Part3/UnionFind/IntMap.hs:60:14
      ‘s1’ is a rigid type variable bound by
           a type expected by the context: UfIntMap s1 () Bool
           at /Users/tel/blog/public/code/MutableImmutable/Part3/UnionFind/IntMap.hs:62:3
    Expected type: Node (UfIntMap s1 ())
      Actual type: Node (UfIntMap s ())
~~~

While our correct example still compiles, albeit needing a new type
annotation

~~~
exPure = runUfIntMap computation where
  computation :: UF r Int => r Bool
  computation = do
    n1 <- node 1
    n2 <- node 2
    link n1 n2
    connected n1 n2
~~~
{: .language-haskell}

~~~
>>> exPure
True
~~~

## Other posts in this series

* [Part 1](http://tel.github.io/2014/07/12/mutable_algorithms_in_immutable_languges_part_1/)

[^uhoh]:I lied a bit here, actually. If you've been following along carefully you'll see that I changed the implementation of `runUfIntMap` *slightly* too. In fact, its new implementation, by most reasonably accounts, ought to be identical to the original one. Unfortunately, it's not, due to how inference on `RankNTypes` is less powerful than you might think it would be. So let this be a mild warning to you, intrepid higher-rank type explorer: *if reasonable, point-free higher rank programs are getting rejected... reintroduce their points*.