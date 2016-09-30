# JS::Minify [![Build Status](https://travis-ci.org/scmorrison/JS-Minify.svg?branch=master)](https://travis-ci.org/scmorrison/JS-Minify)

JavaScript minifier module for [Perl 6](https://perl6.org). This is a port of the [Perl](https://perl.org) [JavaScript::Minifier](https://metacpan.org/pod/JavaScript::Minifier) module.

# Synopsis

To minify a JavaScript file and have the output written directly to another file

```perl6
use JS::Minify;

my $in  = open 'myScript.js' or die;
my $out = open 'myScript-min.js' or die;

js-minify(input => $in, outfile => $out);
```

To minify a JavaScript string literal. Note that by omitting the outfile parameter a the minified code is returned as a string.

```perl6
my minified_javascript = js-minify(input => 'var x = 2;');
```

To include a copyright comment at the top of the minified code.

```
js-minify(input => 'var x = 2;', copyright => 'BSD License');
```

To treat ';;;' as '//' so that debugging code can be removed. This is a common JavaScript convention for minification.

```perl6
js-minify(input => "var x = 2;\n;;;alert('hi');\nvar x = 2;", stripDebug => 1)
# output: 'var x=2;var x=2;'
```

The `input` parameter is mandatory. The `output`, `copyright`, and `strip_debug` parameters are optional and can be used in any combination.

# Description

This module removes unnecessary whitespace from JavaScript code. The primary requirement developing this module is to not break working code: if working JavaScript is in input then working JavaScript is output. It is ok if the input has missing semi-colons, snips like '++ +' or '12 .toString()', for example. Internet Explorer conditional comments are copied to the output but the code inside these comments will not be minified.

The ECMAScript specifications allow for many different whitespace characters: space, horizontal tab, vertical tab, new line, carriage return, form feed, and paragraph separator. This module understands all of these as whitespace except for vertical tab and paragraph separator. These two types of whitespace are not minimized.

For static JavaScript files, it is recommended that you minify during the build stage of web deployment. If you minify on-the-fly then it might be a good idea to cache the minified file. Minifying static files on-the-fly repeatedly is wasteful.

## Export

Exported by default: `js-minifiy()`

# See Also

[JavaScript::Minifier](https://metacpan.org/pod/JavaScript::Minifier) (Perl)

# Repository

You can obtain the latest source code and submit bug reports on the github repository for this module:
[https://github.com/scmorrison/JS-Minify](https://github.com/scmorrison/JS-Minify).

# Gotchas

* *bug*: There module [issue](https://github.com/scmorrison/JS-Minify/issues/1) treats opening '/' on the regex is actually a division, because the previous word "return" ends on an alphanumeric character ( basically, it thinks the regex is the beginning of " n / SOMETHING".

# Author

* Sam Morrison, [scmorrison](https://github.com/scmorrison/)

# Original Authors

* Zoffix Znet, <zoffix@cpan.org> [https://metacpan.org/author/ZOFFIX](https://metacpan.org/author/ZOFFIX)
* Peter Michaux, <petermichaux@gmail.com>
* Eric Herrera, <herrera@10east.com>
* Miller 'tmhall' Hall
* Вячеслав 'vti' Тихановский

# License Information

"JS::Minify" is free software; you can redistribute it and/or modify it under the terms of the Artistic License 2.0. (Note that, unlike the Artistic License 1.0, version 2.0 is GPL compatible by itself, hence there is no benefit to having an Artistic 2.0 / GPL disjunction.) See the file LICENSE for details.

