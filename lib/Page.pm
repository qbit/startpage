# vim: set ts=4 sw=4 tw=0:
# vim: set expandtab:

package Page;

use 5.10.0;
use feature 'signatures';
use feature 'say';
use strict;
use warnings;
use Data::Dumper;

use Exporter 'import';

use JSON qw( from_json );
use Git;

our @ISA       = qw( Exporter );
our @EXPORT_OK = qw( $page slurp update_gh_feed update_prs gh_ignore_number );

my $termQL = q{
    {
      search(query: "is:open is:public archived:false repo:nixos/nixpkgs in:title %s", type: ISSUE, first: 10) {
        issueCount
        edges {
          node {
            ... on Issue {
              number
              title
              url
              repository {
                nameWithOwner
              }
              createdAt
            }
            ... on PullRequest {
              number
              title
              repository {
                nameWithOwner
              }
              createdAt
              url
            }
          }
        }
      }
    }
};

$ENV{"GIT_CONFIG_SYSTEM"} = "";        # Ignore insteadOf rules
$ENV{"HOME"}              = "/tmp";    # Ignore ~/.netrc
Git::command( 'clone', 'https://github.com/nixos/nixpkgs', '/tmp/nixpkgs' )
  if !-e '/tmp/nixpkgs';
my $repo = Git->repository( Directory => '/tmp/nixpkgs' );

our $page = {
    title        => "startpage",
    descr        => "a page to start with",
    feedUpdated  => time(),
    prsUpdated   => time(),
    pullrequests => [
        {
            repo   => "NixOS/nixpkgs",
            number => 194589,
            info   => {
                commit   => '',
                branches => []
            }
        },
        {
            repo   => "NixOS/nixpkgs",
            number => 193186,
            info   => {
                commit   => 'b2c770b9934842892392f805300c785af517ea95',
                branches => []
            }
        },
        {
            repo   => "newrelic/go-agent",
            number => 567,
            info   => {
                thing => "stuff"
            }
        }
    ],
    links => [
        {
            name => "Bold Daemon Stats",
            url  =>
"https://graph.tapenet.org/d/lawL-fMVz/bold-daemon?orgId=1&refresh=5s"
        },
        {
            name => "Books",
            url  => "https://books.bold.daemon"
        },
        {
            name => "LibReddit",
            url  => "https://reddit.bold.daemon"
        },
        {
            name => "MammothCirc.us",
            url  => "https://mammothcirc.us"
        }
    ],

    terms => {
        calibre           => [],
        "element-desktop" => [],
        "matrix-synapse"  => [],
        nheko             => [],
        obsidian          => [],
        restic            => [],
        tailscale         => [],
        "tidal-hifi"      => [],
        openssh           => [],
    }
};

sub slurp {
    my $f = shift;

    open my $fh, '<', $f or die;

    local $/ = undef;

    my $d = <$fh>;
    close $fh;

    chomp $d;
    return $d;
}

sub gh_ignore_number {
    my ($number, $repo) = @_;
    # TODO: Pull this from somewhere fancy
    my $ignores = {
        "NixOS/nixpkgs" => [
            172043,
            160638,
            85587,
            73110,
            35457,
            142453,
            120228
        ]
    };

    return 0 unless defined $ignores->{$repo};
    return 1 if ( grep /$number/, @{$ignores->{$repo}} );

    return 0;
}

sub check_nixpkg_branches {
    my $commit = shift;
    my $list = [];

    return $list if $commit eq "";

    my $branches = $repo->command( 'branch', '-r', '--contains', $commit );

    foreach my $b ( split( '\n', $branches ) ) {
        $b =~ s/^\s+origin\///g;
        push( @$list, $b ) if $b =~ m/unstable/;
    }

    return $list;
}

sub update_prs {
    my $ua = shift;

    $repo->command('fetch');

    foreach my $pr ( sort @{ $page->{pullrequests} } ) {
        if ( defined $pr->{info}->{commit} ) {
            $pr->{info}->{branches} =
              check_nixpkg_branches( $pr->{info}->{commit} );
        }
    }
    $page->{prsUpdated} = time();
}

sub update_gh_feed {
    my $ua = shift;
    foreach my $term ( sort keys %{ $page->{terms} } ) {
        my $q  = sprintf( $termQL, $term );
        my $tx = $ua->post(
            'https://api.github.com/graphql' => json => { query => $q } );
        my $j = from_json $tx->result->body;
        $page->{terms}->{$term} = [];
        foreach my $node ( @{ $j->{data}->{search}->{edges} } ) {
            my $repo = $node->{node}->{repository}->{nameWithOwner};
            say Dumper $repo;
            if (gh_ignore_number($node->{node}->{number}, $repo)) {
                say "ignoring $repo / $node->{node}->{number}";
            } else {
                push( @{ $page->{terms}->{$term} }, $node->{node} );
            }
        }
        Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
    }
    $page->{feedUpdated} = time();
}

1;
