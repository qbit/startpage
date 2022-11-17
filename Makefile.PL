use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => 'startpage',
    VERSION_FROM      => 'startpage.pl',
    EXE_FILES         => [qw(startpage.pl)],
    LICENSE           => 'ISC',
    MIN_PERL_VERSION  => '5.006',
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources => {
            repository => {
                type => 'git',
                url  => 'https://github.com/qbit/startpage.git',
                web  => 'https://github.com/qbit/startpage',
            },
        },
    },
    PMLIBDIRS         => [ 'lib' ],
    PREREQ_PM         => {
	    'JSON' => '0',
	    'Mojolicious' => '0',
	    'Mojo::SQLite' => '0',
	    'IO::Socket::SSL' => '0',
	    'Git' => '0',
    },
);
