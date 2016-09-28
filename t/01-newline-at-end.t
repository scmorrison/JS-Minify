use v6;
use Test;
use Test::Output;
use lib 'lib';
use JS::Minify;
 
plan 2;

# This test ensures that if the file contains a new line at the end
# then that newline will be preserved
# The read-from-file tests for this are in JavaScript-Minifier.t
 
my $js_with_new_line = q:to/EOS/;
function (s) { alert("Foo"); }

EOS
 
my $js_without_new_line = $js_with_new_line.chomp;

my $t1 = js-minify(input => $js_with_new_line);
like $t1, /'\n'$/, 'Last new line was preserved';
 
my $t2 = js-minify(input => $js_without_new_line);
like $t2, /<-[\n]>$/, 'Last new line was not added because it was absent originally',
