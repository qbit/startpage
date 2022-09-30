#!/usr/bin/env perl

# vim: set ts=4 sw=4 tw=0:
# vim: set expandtab:

use strict;
use warnings;
use Time::HiRes qw( time );

use Data::Dumper;

use JSON qw( from_json );

use 5.10.0;

use Mojolicious::Lite -signatures;
use Mojo::IOLoop;
use Mojo::URL;
use Mojo::UserAgent;

sub slurp {
    my $f = shift;

    open my $fh, '<', $f or die;

    local $/ = undef;

    my $d = <$fh>;
    close $fh;

    chomp $d;
    return $d;
}

my $TOKEN = slurp('/run/secrets/nix_review');

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

my $ua = Mojo::UserAgent->new;
$ua->on(
    start => sub ( $ua, $tx ) {
        $tx->req->headers->header( "Authorization" => "Bearer ${TOKEN}" );
    }
);

my $page = {
    title        => "startpage",
    descr        => "a page to start with",
    feedUpdated  => localtime,
    pullrequests => [
        {
            repo   => "NixOS/nixpkgs",
            number => 193186,
            info   => {}
        },
        {
            repo   => "newrelic/go-agent",
            number => 567,
            info   => {}
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
        tailscale         => [],
        "matrix-synapse"  => [],
        nheko             => [],
        obsidian          => [],
        restic            => [],
        "element-desktop" => [],
        "tidal-hifi"      => []
    }
};

sub update_feeds {
    foreach my $term ( sort keys %{ $page->{terms} } ) {
        my $q = sprintf( $termQL, $term );
        $ua->post(
            'https://api.github.com/graphql' => json => { query => $q } =>
              sub ( $ua, $tx ) {
                my $j = from_json $tx->result->body;
                $page->{terms}->{$term} = [];
                foreach my $node ( @{ $j->{data}->{search}->{edges} } ) {
                    push @{ $page->{terms}->{$term} }, $node->{node};
                }
            }
        );
    }
    $page->{feedUpdated} = time();
}

Mojo::IOLoop->timer( 15 * 60 => sub ($loop) { update_feeds } );
update_feeds;

get '/' => sub ($c) {
    $page->{date} = localtime;

    $c->stash( page => $page );
    $c->render( template => 'index' );
};

get '/style.css' => sub ($c) {
    $c->render( template => 'style', format => 'css' );
};

get '/update_feeds' => sub ($c) {
    my $start = time();
    update_feeds;
    my $end     = time();
    my $elapsed = sprintf( "%2f\n", $end - $start );
    $c->render( text => $elapsed );
};

app->start;

__DATA__
@@ index.html.ep
% layout 'default';
<h3><%= $page->{date} %>
<hr />
<div class="list">
  <div class="list_head">
    <p>NixOS Issues / PRs</p>
  </div>
  <hr />
  <p><i>Updated <%= sprintf( "%.1f\n", (time() - $page->{feedUpdated}) / 60 ) %> minutes ago.</i></p>
  <ul>
  % foreach my $term (sort keys %{$page->{terms}}) {
    % if (scalar(@{$page->{terms}->{$term}}) > 0) {
    <li>
      <%= $term %>
      <ul>
      % foreach my $entry (@{$page->{terms}->{$term}}) {
          <li>
            <a target="_blank" href="<%= $entry->{url} %>"><%= $entry->{title} %></a>
          </li>
      % }
      </ul>
    </li>
    % }
  % }
  </ul>
</div>
<div class="list">
  <div class="list_head">
    <p>Pull Requests</p>
  </div>
  <hr />
  <ul>
  % foreach my $pr (sort { $a->{createdAt} <=> $b->{createdAt} } @{$page->{pullrequests}}) {
    <li>
      <a target="_blank" href="https://github.com/<%= $pr->{repo} %>/pull/<%= $pr->{number} %>">
      % if ($pr->{repo} eq "NixOS/nixpkgs") {
        <%= $pr->{repo} %>:<%= $pr->{number} %> ( <a href="https://nixpk.gs/pr-tracker.html?pr=<%= $pr->{number} %>">NPRT</a> )
      % } else {
        <%= $pr->{repo} %>:<%= $pr->{number} %>
      % }
      </a>
    </li>
  % }
  </ul>
</div>
<div class="list">
  <div class="list_head">
    <p>Links</p>
  </div>
  <hr />
  <ul>
  % foreach my $link (@{$page->{links}}) {
    <li><a target="_blank" href="<%= $link->{url} %>"><%= $link->{name} %></a></li>
  % }
  </ul>
</div>

@@ layouts/default.html.ep
<!doctype html>
<html class="no-js" lang="">
  <head>
    <title><%= $page->{title} %></title>
    <meta charset="utf-8">
    <meta http-equiv="x-ua-compatible" content="ie=edge">
    <meta name="description" content="<%= $page->{descr} %>">
    <link rel="stylesheet" href="/style.css">
  </head>
  <body>
    <div class="results">
      <%== content %>
    </div>
  </body>
</html>

@@ style.css.ep
body {
  background-color: #ffffea;
  text-align: center;
  font-family: Avenir, 'Open Sans', sans-serif;
}

.results {
    width: 98%;
    border: 1px solid black;
    overflow: hidden;
    padding: 10px;
    border-radius: 10px;
}

.list {
    width: 30%;
    float: left;
    border: 1px solid black;
    text-align: left;
    padding-left: 10px;
    padding-right 10px;
    margin: 10px;
    border-radius: 10px;
	box-shadow: 2px 2px 2px black;
}

.list_head {
    //background-color: #eaeaff;
}

.list p {
    padding-left: 10px;
}
