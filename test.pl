
use JSON;
use File::stat;
use Data::Dumper;
use POSIX;

#my $o = { Abc => 'Foo bar', Def => [ 3.14, 42, 'Ghi' ], Jkl => { Mno => true, Pqr => undef} };
#print (encode_json $o), "\n";
#print JSON->new->allow_nonref->pretty->encode($o), "\n";

my $m = {};

for (map { glob } @ARGV) {
    my $stats = stat($_) 
        or die "Couldn't stat $_: $!";
     
    #print Dumper($stats), "\n";  
    
    $md5 = "0123456789abcef";
    $fullMd5 = "0123456789abcef0123456789abcef";
    
    $m->{$_} = {
        md5 => $md5,
        full_md5 => $fullMd5,
        size => $stats->size,
        mtime => $stats->mtime,
    };
}

print JSON->new->allow_nonref->pretty->encode($m), "\n";

print "FIN!\n";