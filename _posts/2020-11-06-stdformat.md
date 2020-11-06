---
layout: post
title: String formatting the cool way with C++20 std::format()
tags: [C++20]
date: 2020-11-06T01:46:34+02:00
comments: false
---

# String formatting the cool way with C++20 `std::format()`

Through its 40 years of history C++ has had multiple "tries" to bring text
formatting to the language. First it was the `printf()` family of functions
inherited from C:

``` cpp
std::printf("hello %s/n", "world!");
```

Succint, well known, "fast", it certainly does the job. It was so successful
due to its ubiquitousness that *"printf-driven-debugging"* became a thing, to
a point that
[debuggers](https://sourceware.org/gdb/current/onlinedocs/gdb/Dynamic-Printf.html#Dynamic-Printf)
and [IDEs](https://code.visualstudio.com/docs/editor/debugging#_logpoints) have
integrated `printf()`-like APIs these days.

> Let's be honest, it's 2020 and we all still do printf-debugging from time to
> time. 

But from its simplicity came its wekaness: `printf()` and related functions
work with built-in C types only (`int`, `const char*` strings, etc), formatting
is not type safe, and the multi-argument API is based on arcane
[`varargs`](https://en.cppreference.com/w/cpp/utility/variadic).

Some years later people started to work on alternatives to the C's IO APIs,
with type safety and integration of user defined types in mind. This work would
became what we now know as the standard
[`<iostream>`](https://en.cppreference.com/w/cpp/header/iostream) library:

``` cpp
const std::string world{"world"};
std::cout << "hello" << world << std::endl;
```

But while it improved on the type safety and extensibility sides, it suffers
from [bad
performance](https://stackoverflow.com/questions/4340396/does-the-c-standard-mandate-poor-performance-for-iostreams-or-am-i-just-deali),
[some arguably bad design
decisions](https://en.cppreference.com/w/cpp/io/ios_base/pword), and
a surprising obsession with chevrons that Richard Dean Anderson would certainly
be proud of: 

``` cpp
std::cout << "oh yeah, "
          << "this is "
          << definitely()
          << " not verbose "
          << *at_all 
          << std::endl;
```

C++20 will bring us a new text formatting API, [the formatting library
`<format>`](https://en.cppreference.com/w/cpp/utility/format), which tries to
overcome the issues of streams but with the simplicity of `printf()`.

## A modern `sprintf()`

`<format>` is a text formatting library based on three simple principles:

 - **Placeholder-based formatting syntax**, with support for indexed arguments and format specifications.
 - **Type-safe formatting**, using variadic templates for
 multiple argument support.
 - **Support for user defined types** through custom formatters.

Its main function,
[`std::format()`](https://en.cppreference.com/w/cpp/utility/format/format),
formats the given arguments and returns a string:

``` cpp
#include <format>

int main()
{
    const std::string message = std::format("{}, {}!", "hello", "world");
}
```

Placeholders can be indexed, allowing us to change the order of the arguments
or even repeat them. This two calls both return `"hello, world!"`:

``` cpp
std::format("{1}, {0}!", "world", "hello");
std::format("he{0}{0}o, {1}!", "l", "world");
```

In adition to `std::format()` the library provides
[`std::format_to()`](https://en.cppreference.com/w/cpp/utility/format/format_to),
which allows us to write the resulting string into an iterator instead of
allocating a `std::string` directly. This comes handy to dump the formatted
string into any kind of iterator-based storage, like a file:

``` cpp
std::ofstream file{"format.txt"};
std::format_to(std::ostream_iterator<char>(file), "hello, {}!", "world");
```

or a container:

``` cpp
std::vector<char> buffer;
std::format_to(std::ostream_iterator<char>(buffer), "hello, world!");
```

So far all the examples involved string arguments, but the format API supports
all kind of types, as long as a formatter is available for them (More on this
later). There are predefined formatters for built-in types (`int`, `bool`,
`std::string`, `std::chrono::duration`, etc) so in most cases It Will Just
Work:

``` cpp
#include <chrono>
#include <format>

const std::string dont_panic =
    std::format("Just {} days left for the release, right?", std::chrono::days(42));
```

Formatters not only return a string representation of a value, but also allow
to customize the output through formatting specifiers. [These
specifiers](https://en.cppreference.com/w/cpp/utility/format/formatter) are
specific to each type formatter, for example the floating-point formatters
implements precision config:

``` cpp
// Save pi as a string with three decimals of precision:
const std::string pi = std::format("{:.3f}", 3.141592654);
```

or you can use type options to control how values are displayed:

``` cpp
const std::string id = std::format("{:#x}", 0xa); // "0xa"
```

## Integrating user defined types

To make our types work with `<format>` there are two ways:

 - Overload `operator<<` for `std::ostream` (As usual with the stream API).
 - Write a custom formatter for your type

The first way is probably the most simple. `<format>` interoperates with the
streams library so that any type compatible with output streams is compatible
with the formatting library:

``` cpp
#include <ostream>
#include <format>

enum class State
{
    On,
    Off
};

std::ostream& operator<<(std::ostream& os, const State state)
{
    switch(state)
    {
    case State::On:
        return os << "On";
    case State::Off:
        return os << "Off";
    }

    // unreachable
    return os;
}

...

const std::string current_mode = std::format("current mode is {}", Mode::On);
```

This has the disadvantage that you add the performance overhead of streams into
the formatting, but it's the easiest way to migrate your existing types to
`<format>` if you already integrated them with `ostream`.


Writing a custom formatter involves specializing the [`std::formatter`
template](https://en.cppreference.com/w/cpp/utility/format/formatter) for your
type:

``` cpp
template<>
struct std::formatter<State>
{
    std::format_parse_context::iterator parse(std::format_parse_context& context)
    {
       ...
    }

    std::format_parse_context::iterator format(
        const State state,
        std::format_context& context)
    {
       ...
    }
};
```

The specialization must contain two member functions:

 - `parse(context)`: In charge of parsing the format specifications in the
 argument placeholder (If there's any). That is, it is the function that parses
 what's inside the "{}" placeholders of the format strings. If any specifier is
 found, it must be stored in the `std::formatter` object (`this` in the context
 of the function).

 - `format(value, context)`: Formats the given value into the given output
 formatting context, applying any formatting specification found previously by
 `parse()`. For formatting to a given context you can simply call
 `std::format_to()` with the iterator provided by the context.

We will not cover parsing in depth here (That are [good reference
examples](https://fmt.dev/latest/api.html#formatting-user-defined-types))
because most of the time you're better off **inheriting from an existing
formatter that does the complicated stuff for you**:

``` cpp
template<>
struct std::formatter<State> : std::formatter<std::string_view>
{
    template<typename Context>
    auto format(const State state, Context& context)
    {
        switch(state)
        {
        case State::On:
            return formatter<std::string_view>::format("On", context);
        case State::Off:
            return formatter<std::string_view>::format("Off", context);
        }

        // unreachable
        return context.out();
    }
}
```

## About fmt

The standard `<format>` API is the result of Victor Zverovich's work on
[`fmt`](https://fmt.dev/), an open source library. Currently `fmt` implements
a subset of features common to the standard `<format>` plus some extra nice
features:

 - `fmt::print()` as substitute for `std::cout`.
 - Colored output with foreground and background modifiers. Built-in support
 - for formatting containers

The library is available [on github](https://github.com/fmtlib/fmt) and [the
major C++](https://conan.io/center/fmt) [package
managers](https://fmt.dev/dev/usage.html#vcpkg).
