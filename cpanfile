requires 'Finance::Contract',   '>= 0.010';
requires 'Time::Duration::Concise';
requires 'Format::Util::Numbers';
requires 'Exporter';
requires 'Date::Utility';
requires 'File::ShareDir';
requires 'Scalar::Util';
requires 'Finance::Underlying';
requires 'Finance::Asset';
requires 'YAML::XS';

on test => sub {
    requires 'Test::More',                      '>= 0.98';
    requires 'Test::Most',                      '>= 0.34';
    requires 'Test::FailWarnings',              '>= 0.008';
};

on develop => sub {
    requires 'Devel::Cover',                    '>= 1.23';
    requires 'Devel::Cover::Report::Codecov',   '>= 0.14';
};
