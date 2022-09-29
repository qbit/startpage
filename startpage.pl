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
use Mojo::UserAgent;
use Mojo::URL;

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
              bodyText
              createdAt
              mergedAt
              url
              changedFiles
              additions
              deletions
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
}

update_feeds;

get '/' => sub ($c) {
    $page->{date} = localtime;

    $c->stash( page => $page );
    $c->render( template => 'index' );
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
<div>
  <p>Pull Requests:</p>
  <ul>
  % foreach my $pr (@{$page->{pullrequests}}) {
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
<div>
  <p>Links:</p>
  <ul>
  % foreach my $link (@{$page->{links}}) {
    <li><a target="_blank" href="<%= $link->{url} %>"><%= $link->{name} %></a></li>
  % }
  </ul>
</div>
<div>
  <p>NixOS Issues / PRs:</p>
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

@@ layouts/default.html.ep
<!doctype html>
<html class="no-js" lang="">
  <head>
    <title><%= $page->{title} %></title>
    <meta charset="utf-8">
    <meta http-equiv="x-ua-compatible" content="ie=edge">
    <meta name="description" content="<%= $page->{descr} %>">
    <style>
    </style>
  </head>
  <body>
    <div class="results">
      <%== content %>
    </div>
  </body>
</html>
