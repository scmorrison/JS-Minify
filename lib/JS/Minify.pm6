use v6;

unit module JS::Minify;

# return true if the character is allowed in identifier.
sub is-alphanum(Int $x) returns Bool {
  $x > 126 || $x.chr ~~ / <[ \$ \\ \w ]> /.Bool ;
}

sub is-endspace(Int $x) returns Bool {
  $x.chr ~~ / \v /.Bool;
}

sub is-whitespace(Int $x) returns Bool {
  $x.chr ~~ / \h /.Bool || is-endspace($x);
}

# New line characters before or after these characters can be removed.
# Not + - / in this list because they require special care.
sub is-infix(Int $x) returns Bool {
  $x.chr ~~ / <[ , ; : = & % * < > ? | \n ]> /.Bool
}

# New line characters after these characters can be removed.
sub is-prefix(Int $x) returns Bool {
  $x.chr ~~ / <[ { ( [ ! ]> /.Bool || is-infix($x);
}

# New line characters before these characters can removed.
sub is-postfix(Int $x) returns Bool {
  $x.chr ~~ / <[ } ) \] ]> /.Bool;
}

sub get(%s is copy) returns List { 
  given %s<input>.elems {
    when *>0 {
      unless %s<input_pos> <= %s<input>.elems {
        [0, %s<last_read_char>, %s<input_pos>];
      }
      my $char = %s<input>[%s<input_pos>];
      my $last_read_char = %s<input>[%s<input_pos>++];
      $char ?? $char !! 0, $last_read_char, %s<input_pos>;
    }
    default {
      die "no input";
    }
  }
}

# print a
# move b to a
# move c to b
# move d to c
# new d
#
# i.e. print a and advance
sub action1(%s) returns Hash {
  %s<lastnws> = %s<a> unless is-whitespace(%s<a>);
  %s<last> = %s<a>;
  action2(%s);
}

# sneeky output %s<a> for comments
sub action2(%s) returns Hash {
  %s<output>.send(%s<a>);
  action3(%s);
}

# move b to a
# move c to b
# move d to c
# new d
#
# i.e. delete a
sub action3(%s) returns Hash {
  %s<a> = %s<b>;
  action4(%s);
}

# move c to b
# move d to c
# new d
#
# i.e. delete b
sub action4(%s is copy) returns Hash {
  %s<b> = %s<c>;
  %s<c> = %s<d>;
  (%s<d>, %s<last_read_char>, %s<input_pos>) = get(%s); 
  return %s;
}

# put string and regexp literals
# when this sub is called, %s<a> is on the opening delimiter character
sub put-literal(%s is copy) returns Hash {
  my $delimiter = %s<a>; # ', " or /
  %s = action1(%s);
  repeat {
    while (%s<a> && %s<a> eq 92) { # \\ escape character only escapes only the next one character
      %s = action1(%s);
      %s = action1(%s);
    }
    %s = action1(%s);
  } until (%s<last> eq $delimiter || !%s<a>);

  given %s<last> {
    when * ne $delimiter { # ran off end of file before printing the closing delimiter
      die 'unterminated single quoted string literal, stopped' if $delimiter eq 39; # \'
      die 'unterminated double quoted string literal, stopped' if $delimiter eq 34; # \"
      die 'unterminated regular expression literal, stopped';
    }
    default { %s }
  }

}

# If %s<a> is a whitespace then collapse all following whitespace.
# If any of the whitespace is a new line then ensure %s<a> is a new line
# when this function ends.
sub collapse-whitespace(%s is copy) returns Hash {
  while (%s<a> && is-whitespace(%s<a>) &&
         %s<b> && is-whitespace(%s<b>)) {
    %s<a> = "\n".ord when (is-endspace(%s<a>) || is-endspace(%s<b>));
    %s = action4(%s); # delete b
  }
  return %s;
}

# Advance %s<a> to non-whitespace or end of file.
# Doesn't print any of this whitespace.
sub skip-whitespace(%s is copy) returns Hash {
  while (%s<a> && is-whitespace(%s<a>)) {
    %s = action3(%s);
  }
  return %s;
}

# Advance %s<a> to non-whitespace or end of file
# If any of the whitespace is a new line then print one new line.
sub preserve-endspace(%s is copy) returns Hash {
  %s = collapse-whitespace(%s);
  %s = action1(%s) when ( %s<a> && is-endspace(%s<a>) && %s<b> && !is-postfix(%s<b>) );
  skip-whitespace(%s);
}

sub on-whitespace-conditional-comment(Int $a, Int $b, Int $c, Int $d) returns Bool {
  ($a && is-whitespace($a) &&
   $b && $b eq 47 && # /
   $c && ($c ~~ 42|47) && # \/ *
   $d && $d eq 64).Bool; # @
}

# Shift char or preserve endspace toggle
sub process-conditional-comment(%s) returns Hash {
  given on-whitespace-conditional-comment(|%s{'a' .. 'd'}) {
    when * eq True { action1(%s) }
    default { preserve-endspace(%s) }
  }
}

# Handle + + and - -
sub process-double-plus-minus(%s) returns Hash {
  given %s<a> {
    when is-whitespace(%s<a>) {
      (%s<b> && %s<b> eq %s<last>) ?? action1(%s) !! preserve-endspace(%s);
    }
    default { %s }
  }
};

# Handle potential property invocations
sub process-property-invocation(%s) returns Hash {
  (given %s<a> {
     when $_ && is-whitespace($_) {
       # if %s<b> is '.' could be (12 .toString()) which is property invocation. If space removed becomes decimal point and error.
      (%s<b> && (is-alphanum(%s<b>) || %s<b> eq 46)) ?? action1(%s) !! preserve-endspace(%s);
     }
     default { %s }
   });
}

#
# process-comments
#
multi sub process-comments(%s is copy where {%s<b> && %s<b> eq 47}) returns Hash { # / a division, comment, or regexp literal
  my $cc_flag = %s<c> && %s<c> eq 64; # @ tests in IE7 show no space allowed between slashes and at symbol

  repeat {
    %s = $cc_flag ?? action2(%s) !! action3(%s);
  } until (!%s<a> || is-endspace(%s<a>));

  # Return %s
  (given $cc_flag {
     when $_ {
       (%s
        ==> action1() # cannot use preserve-endspace(%s) here because it might not print the new line
        ==> skip-whitespace());
     }
     when %s<last> && !is-endspace(%s<last>) && !is-prefix(%s<last>) {
       preserve-endspace(%s);
     }
     default {
       skip-whitespace(%s);
     }
  });

}

multi sub process-comments(%s is copy where {%s<b> && %s<b> eq 42}) returns Hash { # slash-star comment
  my $cc_flag = %s<c> && %s<c> eq 64; # @ test in IE7 shows no space allowed between star and at symbol

  repeat { 
    %s = $cc_flag ?? action2(%s) !! action3(%s);
  } until (!%s<b> || (%s<a> eq 42 && %s<b> eq 47)); # * /

  die 'unterminated comment, stopped' unless %s<b>; # %s<a> is asterisk and %s<b> is foreslash

  # Return %s
  (given $cc_flag {
     when $_ {
       (%s
        ==> action2() # the *
        ==> action2() # the /
        # inside the conditional comment there may be a missing terminal semi-colon
        ==> preserve-endspace());
     }
     default { # the comment is being removed
      %s = action3(%s); # the *
      %s<a> = ' '.ord;  # the /
      %s = collapse-whitespace(%s);
      if (%s<last> && %s<b> &&
        ((is-alphanum(%s<last>) && (is-alphanum(%s<b>)||%s<b> eq 46)) || # . period
        #            +              +                   -              -
        (%s<last> eq 43 && %s<b> eq 43) || (%s<last> eq 45 && %s<b> eq 45))) { # for a situation like 5-/**/-2 or a/**/a
        # When entering this block %s<a> is whitespace.
        # The comment represented whitespace that cannot be removed. Therefore replace the now gone comment with a whitespace.
        action1(%s);
      } elsif (%s<last> && !is-prefix(%s<last>)) {
        preserve-endspace(%s);
      } else {
        skip-whitespace(%s);
      }
    }
  });
}

multi sub process-comments(%s is copy where {%s<lastnws> && 
                           (%s<lastnws> ~~ 41|93|46  || # \) \] \.
                            is-alphanum(%s<lastnws>))}) returns Hash {  # division
 action1(%s)
 ==> collapse-whitespace()
 # don't want closing delimiter to
 # become a slash-slash comment with
 # following conditional comment
 ==> process-conditional-comment();
}


multi sub process-comments(%s is copy where {%s<a> eq 47 and %s<b> eq 46 }) returns Hash { # / .
  collapse-whitespace(%s)
  ==> action1();
}

multi sub process-comments(%s is copy) returns Hash {
  put-literal(%s)
  ==> collapse-whitespace()
  # we don't want closing delimiter to
  # become a slash-slash comment with
  # following conditional comment
  ==> process-conditional-comment();
}

#
# process-char
#
multi sub process-char(%s where {%s<a> eq 47}) returns Hash { # a division (/), comment, or regexp literal
  process-comments(%s);
}

multi sub process-char(%s where { %s<a> ~~ 34|39}) returns Hash { # string literal (' ")
  put-literal(%s)
  ==> preserve-endspace();
}

multi sub process-char(%s where { %s<a> ~~ 43|45}) returns Hash { # careful with + + and - -
  action1(%s)
  ==> collapse-whitespace()
  ==> process-double-plus-minus();
}

multi sub process-char(%s where {is-alphanum(%s<a>)}) returns Hash { # keyword, identifiers, numbers
  action1(%s)
  ==> collapse-whitespace()
  ==> process-property-invocation();
}

multi sub process-char(%s where {%s<a> ~~ 41|93|125}) returns Hash { # ] } )
  action1(%s)
  ==> preserve-endspace();
}

multi sub process-char(%s is copy) returns Hash {
  action1(%s)
  ==> skip-whitespace();
}

# Decouple the output processing.
# Either send output to a client
# provided Channel, or to a fully
# minified string.
#
# Output to Stream
#
multi sub output-manager(Channel $output, Channel $stream) returns Promise {
  start {
    # Read from client supplied channel
    $output.list.map: -> $c {
      # Exit when 'exit'
      if $c eq 'exit' {
        $stream.close;
        last;
      }
      # Stream to client channel
      $stream.send($c.chr);
    }
    return;
  }
}
#
# Output to String
#
multi sub output-manager(Channel $output) returns Promise {
  start {
    my $output_text;
    # Read from client supplied channel
    $output.list.map: -> $c {
      # Exit when 'exit'
      last if $c eq 'exit';
      # Store to output
      $output_text ~= $c.chr;
    }

    # Return fully minified result when
    # not streaming to client
    $output_text;
  }
}

#
# js-minify
#
sub js-minify(:$input!, :$copyright = '', :$stream = Empty, :$strip_debug = 0) is export {

  # Immediately turn hash into a hash reference so that notation is the same in this function
  # as others. Easier refactoring.

  # Capture inpute / readchars from file into string
  my $input_new = ($input.WHAT ~~ Str ?? $input !! $input.readchars.chomp);

  # Store all chars in List
  my $input_list = (given $strip_debug {
                      when 1  { $input_new.subst( /';;;' <-[\n]>+/, '', :g) }
                      default { $input_new }
                    });

  # hash reference for "state". This module
  my %s = (input          => $input_list.ords.cache,
           strip_debug    => $strip_debug,
           last_read_char => 0,
           input_pos      => 0,
           output         => Channel.new,
           last           => Empty, # assign for safety
           lastnws        => Empty).Hash; # assign for safety

  # Capture output either to client supplied stream (Channel)
  # or to $output as string to return upon completion.

  my $output = (given $stream {
                  when Channel { output-manager(%s<output>, $stream) }
                  default      { output-manager(%s<output>) }
                });

  # Print the copyright notice first
  if ($copyright) {
    "/* $copyright */".ords».&{%s<output>.send($_)};
  }

  # Initialize the buffer (first four characters to analyze)
  repeat {
    (%s<a>, %s<last_read_char>, %s<input_pos>) = get(%s); 
  } while (%s<a> && is-whitespace(%s<a>));
  (%s<b>, %s<last_read_char>, %s<input_pos>) = get(%s); 
  (%s<c>, %s<last_read_char>, %s<input_pos>) = get(%s);
  (%s<d>, %s<last_read_char>, %s<input_pos>) = get(%s); 

  # Wrap main character processing in Promise 
  # to decouple it from output process
  start {

    while %s<a> { # on this line %s<a> should always be a
                  # non-whitespace character or '' (i.e. end of file)

      if (is-whitespace(%s<a>)) { # check that this program is running correctly
        die 'minifier bug: minify while loop starting with whitespace, stopped';
      }
        
      # Each branch handles trailing whitespace and ensures
      # %s<a> is on non-whitespace or '' when branch finishes
      %s = process-char(%s);
    };


    # Return \n if input included it
    %s<output>.send(10) when %s<input>.tail.chr eq "\n";

    # Send 'done' to exit react/whenever block
    %s<output>.send('exit');
  }

  # return output
  $output.result unless $stream ~~ Channel;
}
