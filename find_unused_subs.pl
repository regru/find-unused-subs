#!/usr/bin/env perl

# usage:
# find /www/srs/lib /www/srs/script -name '*.*' | egrep "\.p[lm]$" | ./find_unused_subs.pl | grep -v "#"

use SRS::Perl;
use Perl::Critic::StricterSubs::Utils;
use Perl::Critic::Utils qw/is_perl_builtin is_function_call is_method_call/;
use PPI::Document;
use Data::Dumper;
use PPI::Find;
use PPI::Dumper;
use Getopt::Long;

my $filter_sub;

main();

sub main {

    my $filter_file;

    my %unused_subs;
    my @files;


    # Опции командной строки

    GetOptions(
        'filter|f=s' => \$filter_file,
        );

    if ( $filter_file && -e $filter_file ) {

        eval {
            do $filter_file; 1
        } || do {
            die "Can't execute $filter_file! $@";
        };

        if ( main->can('process_filter') ) {
            #no strict;
            $filter_sub = \&main::process_filter;
        }
    }

    # Получаем список файлов

    while( my $str = <>) {
        chomp $str;
        push @files, $str;
    }

    # Собираем сабрутины

    for my $file (@files) {
        my $doc = PPI::Document->new($file);
        collect_declared_subs(\%unused_subs, $file, $doc);
    }

    # Ищем вызовы

    for my $file (@files) {
        my $doc = PPI::Document->new($file);
        for my $elem ( find_subroutine_or_method_calls($doc) ){
            my $subname = $elem->content;
            $subname =~ s/^&//;
            if ($subname =~ /::/) {
                my $shortname = $subname;
                $shortname =~ s{\A .*::}{}mx;
                if ($unused_subs{$shortname} && $unused_subs{$shortname}{fullname} eq $subname) {
                    delete $unused_subs{$shortname};
                    print "# fullname_delete\t", $subname, "\n";
                }
            }
            else {
                print "# shortname_delete\t", $subname, "\n";
                delete $unused_subs{$subname};
            }
            print "# call\t", $subname, "\n";
        }
    }


    # Вывод данных

    my %data;
    for my $subrec (values %unused_subs) {
        push @{ $data{ $subrec->{file} } ||= [] }, $subrec->{fullname};
    }

    for my $file (sort keys %data) {
        for my $sub (@{$data{$file}}) {
            print "$file $sub\n";
        }
    }

}

sub collect_declared_subs {
    my ($unused_subs, $file, $doc) = @_;
    my $curpkg = 'main';
    my $doc_content = $doc->content;
    $doc->find(sub {
        my ($doc, $elem) = @_;
        if ($elem->isa('PPI::Statement::Sub')) {
            my $subname = $elem->name();
            my $fullname;
            if ($subname =~ /::/) {
                $fullname = $subname;
                $subname =~ s{\A .*::}{}mx ;
            }
            else {
                $fullname = "${curpkg}::$subname";
            }

            return 1 if $subname =~ /^[A-Z]+$/;

            return 1
                if $filter_sub->(
                    current_package => $curpkg,
                    sub_name        => $subname,
                    doc_content     => $doc_content,
                    );

            print "# add\t", $subname, "\t", $fullname, "\t", $file, "\n";
            $unused_subs->{$subname} = { fullname => $fullname, file => $file };

        }
        elsif ($elem->isa('PPI::Statement::Package')) {
            $curpkg = $elem->namespace;
        }
        return 1;
    });
}

sub find_subroutine_or_method_calls {
    my ($doc) = @_;

    my $sub_calls_ref = $doc->find( \&_is_subroutine_callx );
    return if not $sub_calls_ref;
    return @{$sub_calls_ref};
}

#-----------------------------------------------------------------------------

sub _is_subroutine_callx {
    my ($doc, $elem) = @_;
    if ( $elem->isa('PPI::Token::Word') ) {

        #return 0 if $elem->content =~ /^BEGIN$/;
        return 0 if is_perl_builtin( $elem );
        return 0 if Perl::Critic::StricterSubs::Utils::_smells_like_filehandle( $elem );
        return 1 if is_function_call( $elem );
        return 1 if is_method_call( $elem );

    }
    elsif ($elem->isa('PPI::Token::Symbol')) {

        return 1 if $elem->symbol_type eq q{&};
    }

    return 0;
}

