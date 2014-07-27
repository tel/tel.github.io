---
layout: post
title: Calkin-Wilf in Swift
---

Previously [I wrote][0] at length about the
[Calkin-Wilf enumeration][1] of rationals. It's an interesting example
of how an anamorphism and catamorphism fuse together to form an
efficient, cute hylomorphism.

[0]:http://tel.github.io/2014/07/09/calkin_wilf_for_early-ish_haskellers/
[1]:http://en.wikipedia.org/wiki/Calkin%E2%80%93Wilf_tree

Or, if you don't speak *X-ism* it's a way of inlining a generator and
its consumer together to build a neat algorithm. It also demonstrates
infinite trees and streams in Haskell.

---

Can we do the same in Swift? Well, lacking laziness we'll need to
delay recursion using functions, but it feels like it ought to work.

~~~
struct Tree<A> {
    let val: A
    let left: () -> Tree<A>
    let right: () -> Tree<A>
}

struct Stream<A> {
    let val: A
    let next: () -> Stream<A>
}
~~~
{: .language-swift}

Here we have an infinite binary tree like we need for modling the
Calkin-Wilf tree. We can generate the Calkin-Wilf tree using recursion

~~~
func calkin(n: Int, m: Int) -> Tree<(Int, Int)> {
    return Tree(
        val: (n, m),
        left: { calkin(n, m) },
        right: { calkin(n, n) }
    )
}
~~~
{: .language-swift}

Note how `{ ... }` brace syntax is used to delay the computation of
the branches of the tree. Since we're building up the tree (and
delaying computation) this is the anamorphism/generator part of the
code.

On the other side, we'd like to "consume"/destroy/fold/reduce this
tree (this is the catamorphism part). For instance, we can flatten a
tree via a breadth-first traversal---which is why I introduced
`Stream` above.

~~~
func traverse<A>(t: Tree<A>) -> Stream<A> {
    return Stream(
        val: t.val,
        next: { interleave(traverse(t.left()), traverse(t.right())) }
    )
}
~~~
{: .language-swift}

Here, `interleave` is a helper function which mixes two streams
together:

~~~
func interleave<A>(sa: Stream<A>, sb: Stream<A>) -> Stream<A> {
    return Stream(
        val: sa.val,
        next: { Stream(
            val: sb.val,
            next: { interleave(sa.next(), sb.next()) }
            )
        }
    )
}
~~~
{: .language-swift}

And we're done. We can stick the ana- and catamorphisms together to
produce an inifinite stream of all of the rational numbers

~~~
let rats: Stream<(Int, Int)> = traverse(calkin(1,1))
~~~
{: .language-swift}

If we build a function to chop off the first few values from a
`Stream` then we can print this (finite) segment and have a complete
program.

~~~
func takeStream<A>(n: Int)(s: Stream<A>) -> [A] {
    var res: [A] = []
    var s = s
    for i in 0..<n {
        res += s.val
        s    = s.next()
    }
    return res
}

func main() {
    println(takeStream(10)(s: rats))
}
~~~
{: .language-swift}

---

Unfortunately, while this passes the syntax and type checkers it won't
compile. Right now the Swift compiler segfaults when trying to compile
(as near as I can tell) anamorphisms/generators.

I've submitted this to Radar. Hopefully it'll be fixed soon as this is
a very powerful technique for producing streaming data!