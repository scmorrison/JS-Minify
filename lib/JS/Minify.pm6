use v6;

unit module Minify::JS;

# return true if the character is allowed in identifier.
sub is-alphanum($x) {
  return ($x ~~ /<[ \w \$ \\ ]>/).Bool || ord($x) > 126;
}

sub is-endspace($x) {
  return ($x ~~ "\n"|"\r"|"\f");
}

sub is-whitespace($x) {
  return ($x ~~ ' '|"\t" || is-endspace($x));
}

# New line characters before or after these characters can be removed.
# Not + - / in this list because they require special care.
sub is-infix($x) {
  return ($x ~~ / <[, ; : = & % * < > \? \| \n ]> /).Bool;
}

# New line characters after these characters can be removed.
sub is-prefix($x) {
  return ($x ~~ / <[ \{ \( \[ ! ]> /).Bool || is-infix($x);
}

# New line characters before these characters can removed.

sub is-postfix($x) {
  return ($x ~~ / <[ \} \) \] ]> /).Bool || is-infix($x);
}

sub get($s) { 
  if ($s<input_type> eq 'file') {
    my $char = getc($s<input>);
    $s<last_read_char> = $char;
    return $char if $char;
  } elsif ($s<input_type> eq 'string') {
    if ($s<input_pos> < $s<input>.chars) {
      return $s<last_read_char> = substr($s<input>, $s<input_pos>++, 1);
    }
    else { # Simulate getc() when off the end of the input string.
      return '';
    }
  }
  else {
   die "no input";
  }
}

sub put($s, $x) {
  my $outfile = ($s<outfile>);
  if $s<outfile> {
    print $outfile, $x;
  } else {
    $s<output> ~= $x;
  }
}

# print a
# move b to a
# move c to b
# move d to c
# new d
#
# i.e. print a and advance
sub action1($s) {
  if (!is-whitespace($s<a>)) {
    $s<lastnws> = $s<a>;    
  }
  $s<last> = $s<a>;
  action2($s);
}

# sneeky output $s<a> for comments
sub action2($s) {
  put($s, $s<a>);
  action3($s);
}

# move b to a
# move c to b
# move d to c
# new d
#
# i.e. delete a
sub action3($s) {
  $s<a> = $s<b>;
  action4($s);
}

# move c to b
# move d to c
# new d
#
# i.e. delete b
sub action4($s) {
  $s<b> = $s<c>;
  $s<c> = $s<d>;
  $s<d> = get($s);
}

# put string and regexp literals
# when this sub is called, $s<a> is on the opening delimiter character
sub put-literal($s) {
  my $delimiter = $s<a>; # ', " or /
  action1($s);
  repeat {
    while ($s<a> && $s<a> ~~ '\\') { # escape character only escapes only the next one character
      action1($s);
      action1($s);
    }
    action1($s);
  } until ($s<last> ~~ $delimiter || !$s<a>);
  if ($s<last> !~~ $delimiter) { # ran off end of file before printing the closing delimiter
  note $s.perl;
    die 'unterminated single quoted string literal, stopped' if $delimiter ~~ '\'';
    die 'unterminated double quoted string literal, stopped' if $delimiter ~~ '"';
    die 'unterminated regular expression literal, stopped';
  }
}

# If $s<a> is a whitespace then collapse all following whitespace.
# If any of the whitespace is a new line then ensure $s<a> is a new line
# when this function ends.
sub collapse-whitespace($s) {
  while ($s<a> && is-whitespace($s<a>) &&
         $s<b> && is-whitespace($s<b>)) {
    if (is-endspace($s<a>) || is-endspace($s<b>)) {
      $s<a> = "\n";
    }
    action4($s); # delete b
  }
}

# Advance $s<a> to non-whitespace or end of file.
# Doesn't print any of this whitespace.
sub skip-whitespace($s) {
  while ($s<a> && is-whitespace($s<a>)) {
    action3($s);
  }
}

# Advance $s<a> to non-whitespace or end of file
# If any of the whitespace is a new line then print one new line.
sub preserve-endspace($s) {
  collapse-whitespace($s);
  if ($s<a> && is-endspace($s<a>) && $s<b> && !is-postfix($s<b>) ) {
    action1($s);
  }
  skip-whitespace($s);
}

sub on-whitespace-conditional-comment($s) {
  return ($s<a> && is-whitespace($s<a>) &&
          $s<b> && $s<b> eq '/' &&
          $s<c> && ($s<c> ~~ / <[ / * ]> /) &&
          $s<d> && $s<d> eq '@');
}

#
# process-comments
#

multi sub process-comments($s where {$s<b> && $s<b> eq '/'}) { # a division, comment, or regexp literal
  my $cc_flag = $s<c> && $s<c> eq '@'; # tests in IE7 show no space allowed between slashes and at symbol
  repeat {
    $cc_flag ?? action2($s) !! action3($s);
  } until (!$s<a> || is-endspace($s<a>));
  if ($s<a>) { # $s<a> is a new line
    if ($cc_flag) {
      action1($s); # cannot use preserve-endspace($s) here because it might not print the new line
      skip-whitespace($s);
    } elsif ($s<last> && !is-endspace($s<last>) && !is-prefix($s<last>)) {
      preserve-endspace($s);
    } else {
      skip-whitespace($s);            
    }
  }
}

multi sub process-comments($s where {$s<b> && $s<b> eq '*'}) { # slash-star comment
  my $cc_flag = $s<c> && $s<c> eq '@'; # test in IE7 shows no space allowed between star and at symbol
  repeat { 
    $cc_flag ?? action2($s) !! action3($s);
  } until (!$s<b> || ($s<a> eq '*' && $s<b> eq '/'));
  if ($s<b>) { # $s<a> is asterisk and $s<b> is foreslash
    if ($cc_flag) {
      action2($s); # the *
      action2($s); # the /
      # inside the conditional comment there may be a missing terminal semi-colon
      preserve-endspace($s);
    } else { # the comment is being removed
      action3($s); # the *
      $s<a> = ' ';  # the /
      collapse-whitespace($s);
      if ($s<last> && $s<b> &&
        ((is-alphanum($s<last>) && (is-alphanum($s<b>)||$s<b> eq '.')) ||
        ($s<last> eq '+' && $s<b> eq '+') || ($s<last> eq '-' && $s<b> eq '-'))) { # for a situation like 5-/**/-2 or a/**/a
        # When entering this block $s<a> is whitespace.
        # The comment represented whitespace that cannot be removed. Therefore replace the now gone comment with a whitespace.
        action1($s);
      } elsif ($s<last> && !is-prefix($s<last>)) {
        preserve-endspace($s);
      } else {
        skip-whitespace($s);
      }
    }
  } else {
    die 'unterminated comment, stopped';
  }
}

multi sub process-comments($s where {$s<lastnws> && 
                          ($s<lastnws> ~~ / <[ ) \] \. ]> / ||
                           is-alphanum($s<lastnws>))}) {  # division
  action1($s);
  collapse-whitespace($s);
  # don't want a division to become a slash-slash comment with following conditional comment
  on-whitespace-conditional-comment($s) ?? action1($s) !! preserve-endspace($s);
}

multi sub process-comments($s where {$s<a> ~~ '/' and $s<b> ~~ '.' }) {
  collapse-whitespace($s);
  action1($s);
}

multi sub process-comments($s) {
  put-literal($s);
  collapse-whitespace($s);
  # don't want closing delimiter to become a slash-slash comment with following conditional comment
  on-whitespace-conditional-comment($s) ?? action1($s) !! preserve-endspace($s);
}

#
# process-char
#

multi sub process-char($s where {$s<a> eq '/'}) { # a division, comment, or regexp literal
  process-comments($s);
}

multi sub process-char($s where {$s<a> ~~ / <[ ' " ]> /}) { # string literal
  put-literal($s);
  preserve-endspace($s);
}

multi sub process-char($s where {$s<a> ~~ / <[+ -]> /}) { # careful with + + and - -
  action1($s);
  collapse-whitespace($s);
  if ($s<a> && is-whitespace($s<a>)) {
     ($s<b> && $s<b> eq $s<last>) ?? action1($s) !! preserve-endspace($s);
  }
}

multi sub process-char($s where {is-alphanum($s<a>)}) { # keyword, identifiers, numbers
  action1($s);
  collapse-whitespace($s);
  if ($s<a> && is-whitespace($s<a>)) {
    # if $s<b> is '.' could be (12 .toString()) which is property invocation. If space removed becomes decimal point and error.
    ($s<b> && (is-alphanum($s<b>) || $s<b> eq '.')) ?? action1($s) !! preserve-endspace($s);
  }
}

multi sub process-char($s where {$s<a> ~~ / <[ \] } ) ]> /}) {
  action1($s);
  preserve-endspace($s);
}

multi sub process-char($s) {
  action1($s);
  skip-whitespace($s);
}

#
# js-minify
#

sub js-minify(:$input!, :$copyright = '', :$output = '', :$outfile = '', :$strip_debug = 0) is export {

  # Immediately turn hash into a hash reference so that notation is the same in this function
  # as others. Easier refactoring.

  # hash reference for "state". This module
  my %s = input => ($strip_debug == 1 ?? $input.subst( /';;;' <-[\n]>+/, '', :g) !! $input);

  # determine if the the input is a string or a file handle.
  if ($input && $input.WHAT ~~ Str) {
    %s<input_pos>  = 0;
    %s<input_type> = 'string';
  } else {
    %s<input_type> = 'file';
  }

  # Determine if the output is to a string or a file.
  if (!$outfile) {
    %s<output> = '';
  }

  # Print the copyright notice first
  if ($copyright) {
    put(%s, '/* ' ~ $copyright ~ ' */');
  }

  # Initialize the buffer.
  repeat {
    %s<a> = get(%s);
  } while (%s<a> && is-whitespace(%s<a>));
  %s<b>       = get(%s);
  %s<c>       = get(%s);
  %s<d>       = get(%s);
  %s<last>    = ''; # assign for safety
  %s<lastnws> = ''; # assign for safety

  while (%s<a>) { # on this line $s<a> should always be a non-whitespace character or '' (i.e. end of file)
    
    if (is-whitespace(%s<a>)) { # check that this program is running correctly
      die 'minifier bug: minify while loop starting with whitespace, stopped';
    }
    
    # Each branch handles trailing whitespace and ensures $s<a> is on non-whitespace or '' when branch finishes
    process-char(%s);
  }
  
  if ( %s<last_read_char> and %s<last_read_char> ~~ /\n/ ) {
    put(%s, '\n');
  }
  
  if (!%s<outfile>) {
    return %s<output>;
  }
  
}
