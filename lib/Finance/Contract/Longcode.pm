package Finance::Contract::Longcode;

use strict;
use warnings;

our $VERSION = '0.001';

=head1 NAME

Finance::Contract::Longcode - contains utility functions to convert a binary.com's shortcode to human readable longcode and shortcode to a hash reference parameters.

=head1 SYNOPSIS

    use Finance::Contract::Longcode qw(shortcode_to_longcode);

    my $longcode = shortcode_to_longcode('PUT_FRXEURNOK_100_1394590423_1394591143_S0P_0','USD');

=head1 DESCRIPTION

Shortcode is a string representation of a binary.com's contract. An example of shortcode would be 'CALL_FRXUSDJPY_100_1393816299_1393828299_S0P_0' where each contract parameter is separated by an underscore.

In the example above:

- CALL is a binary.com's contract type
- FRXUSDJPY is a binary.com's symbol for an financial instrument
- 100 is the payout of the contract
- 1393816299 is the start time of the contract, in epoch.
- 1393828299 is the expiration time of the contract, in epoch.
- S0P is the first strike representation of the contract.
- 0 is the second strike representation of the contract.

Longcode is the human readable representation of the shortcode. The longcode for the example above would be translated to 'Win payout if USD/JPY is strictly higher than entry spot at 12 minutes after contract start time'.

=cut

use Date::Utility;
use Exporter qw(import);
use File::ShareDir ();
use Finance::Contract::Category;
use Finance::Underlying;
use Finance::Asset;
use Format::Util::Numbers qw(formatnumber);
use Scalar::Util qw(looks_like_number);
use Time::Duration::Concise::Localize;
use YAML::XS qw(LoadFile);

our @EXPORT_OK = qw(shortcode_to_longcode shortcode_to_parameters get_longcodes);

use constant {
    SECONDS_IN_A_DAY         => 86400,
    FOREX_BARRIER_MULTIPLIER => 1e6,
};

my $LONGCODES = LoadFile(File::ShareDir::dist_file('Finance-Contract-Longcode', 'longcodes.yml'));

=head2 get_longcodes

Returns a hash reference of longcode related strings

=cut

sub get_longcodes {
    return $LONGCODES;
}

=head2 shortcode_to_longcode

Converts shortcode to human readable longcode. Requires a shortcode.

Returns an array reference of strings.

=cut

sub shortcode_to_longcode {
    my ($shortcode) = @_;

    my $params = shortcode_to_parameters($shortcode);

    if ($params->{bet_type} eq 'Invalid') {
        return $LONGCODES->{legacy_contract};
    }

    if ($params->{bet_type} !~ /ico/i && !(defined $params->{date_expiry} || defined $params->{tick_count})) {
        die 'Invalid shortcode. No expiry is specified.';
    }

    my $underlying          = Finance::Underlying->by_symbol($params->{underlying});
    my $contract_type       = $params->{bet_type};
    my $is_forward_starting = $params->{starts_as_forward_starting};
    my $date_start          = Date::Utility->new($params->{date_start});
    my $date_expiry         = Date::Utility->new($params->{date_expiry});
    my $expiry_type         = $params->{tick_expiry} ? 'tick' : $date_expiry->epoch - $date_start->epoch > SECONDS_IN_A_DAY ? 'daily' : 'intraday';
    $expiry_type .= '_fixed_expiry' if $expiry_type eq 'intraday' && !$is_forward_starting && $params->{fixed_expiry};

    my $longcode_key = lc($contract_type . '_' . $expiry_type);

    die 'Could not find longcode for ' . $longcode_key unless $LONGCODES->{$longcode_key};

    my @longcode = ($LONGCODES->{$longcode_key}, $underlying->display_name);

    my ($when_end, $when_start) = ([], []);
    if ($expiry_type eq 'intraday_fixed_expiry') {
        $when_end = [$date_expiry->datetime . ' GMT'];
    } elsif ($expiry_type eq 'intraday') {
        $when_end = {
            class => 'Time::Duration::Concise::Localize',
            value => $date_expiry->epoch - $date_start->epoch
        };
        $when_start = ($is_forward_starting) ? [$date_start->db_timestamp . ' GMT'] : [$LONGCODES->{contract_start_time}];
    } elsif ($expiry_type eq 'daily') {
        $when_end = [$LONGCODES->{close_on}, $date_expiry->date];
    } elsif ($expiry_type eq 'tick') {
        $when_end   = [$params->{tick_count}];
        $when_start = [$LONGCODES->{first_tick}];
    }

    push @longcode, ($when_start, $when_end);

    if ($contract_type =~ /DIGIT/) {
        push @longcode, $params->{barrier};
    } elsif (exists $params->{high_barrier} && exists $params->{low_barrier}) {
        push @longcode, map { _barrier_display_text($_, $underlying) } ($params->{high_barrier}, $params->{low_barrier});
    } elsif (exists $params->{barrier}) {
        push @longcode, _barrier_display_text($params->{barrier}, $underlying);
    } else {
        # the default to the pip size of an underlying
        push @longcode, [$underlying->pip_size];
    }

    return \@longcode;
}

=head2 shortcode_to_parameters

Converts shortcode to a hash reference parameters. Requires shortcode.

Optional parameters:

- currency is provided if you wish to have a complete list of parameters to create a contract.
- is_sold is to indicate of a contract is sold.

Returns a hash reference.

=cut

sub shortcode_to_parameters {
    my ($shortcode, $currency, $is_sold) = @_;

    $is_sold //= 0;

    my ($bet_type, $underlying_symbol, $payout, $date_start, $date_expiry, $barrier, $barrier2, $prediction, $fixed_expiry, $tick_expiry,
        $how_many_ticks, $forward_start, $binaryico_per_token_bid_price,
        $binaryico_number_of_tokens, $binaryico_deposit_percentage, $contract_multiplier);

    my ($initial_bet_type) = split /_/, $shortcode;

    my $legacy_params = {
        bet_type   => 'Invalid',    # it doesn't matter what it is if it is a legacy
        underlying => 'config',
        currency   => $currency,
    };

    return $legacy_params if (not exists Finance::Contract::Category::get_all_contract_types()->{$initial_bet_type} or $shortcode =~ /_\d+H\d+/);

    if ($shortcode =~ /^([^_]+)_([\w\d]+)_(\d*\.?\d*)_(\d+)(?<start_cond>F?)_(\d+)(?<expiry_cond>[FT]?)_(S?-?\d+P?)_(S?-?\d+P?)(_*)(\d*\.?\d*)$/)
    {                               # Both purchase and expiry date are timestamp (e.g. a 30-min bet)
        $bet_type          = $1;
        $underlying_symbol = $2;
        $payout            = $3;
        $date_start        = $4;
        $forward_start     = 1 if $+{start_cond} eq 'F';
        $barrier           = $8;
        $barrier2          = $9;
        $fixed_expiry      = 1 if $+{expiry_cond} eq 'F';
        if ($+{expiry_cond} eq 'T') {
            $tick_expiry    = 1;
            $how_many_ticks = $6;
        } else {
            $date_expiry = $6;
        }
        $contract_multiplier = $11;
    } elsif ($shortcode =~ /^([^_]+)_(R?_?[^_\W]+)_(\d*\.?\d*)_(\d+)_(\d+)(?<expiry_cond>[T]?)$/) {    # Contract without barrier
        $bet_type          = $1;
        $underlying_symbol = $2;
        $payout            = $3;
        $date_start        = $4;
        if ($+{expiry_cond} eq 'T') {
            $tick_expiry    = 1;
            $how_many_ticks = $5;
        }
    } elsif ($shortcode =~ /^BINARYICO_(\d+\.?\d*)_(\d+)(?:_(\d)+)?$/) {
        $bet_type                      = 'BINARYICO';
        $underlying_symbol             = 'BINARYICO';
        $binaryico_per_token_bid_price = $1;
        $binaryico_number_of_tokens    = $2;
        $binaryico_deposit_percentage  = $3;
    } else {
        return $legacy_params;
    }

    $barrier = _strike_string($barrier, $underlying_symbol, $bet_type)
        if defined $barrier;
    $barrier2 = _strike_string($barrier2, $underlying_symbol, $bet_type)
        if defined $barrier2;
    my %barriers =
        ($barrier and $barrier2)
        ? (
        high_barrier => $barrier,
        low_barrier  => $barrier2
        )
        : (defined $barrier) ? (barrier => $barrier)
        :                      ();

    my $bet_parameters = {
        shortcode    => $shortcode,
        bet_type     => $bet_type,
        underlying   => $underlying_symbol,
        amount_type  => 'payout',
        amount       => $payout,
        date_start   => $date_start,
        date_expiry  => $date_expiry,
        prediction   => $prediction,
        currency     => $currency,
        fixed_expiry => $fixed_expiry,
        tick_expiry  => $tick_expiry,
        tick_count   => $how_many_ticks,
        is_sold      => $is_sold,
        ($forward_start) ? (starts_as_forward_starting => $forward_start) : (),
        %barriers,
    };

    # List of lookbacks
    my $nonbinary_list = 'LBFIXEDCALL|LBFIXEDPUT|LBFLOATCALL|LBFLOATPUT|LBHIGHLOW';
    if ($bet_type =~ /$nonbinary_list/) {
        $bet_parameters->{unit}                = $payout;
        $bet_parameters->{contract_multiplier} = $contract_multiplier;
    }

    # ICO
    if ($bet_type eq 'BINARYICO') {
        $bet_parameters->{amount_type}                   = 'stake';
        $bet_parameters->{amount}                        = $binaryico_per_token_bid_price;
        $bet_parameters->{binaryico_number_of_tokens}    = $binaryico_number_of_tokens;
        $bet_parameters->{binaryico_per_token_bid_price} = $binaryico_per_token_bid_price;
        $bet_parameters->{binaryico_deposit_percentage}  = $binaryico_deposit_percentage;
    }

    return $bet_parameters;
}

## INTERNAL METHODS ##

sub _barrier_display_text {
    my ($supplied_barrier, $underlying) = @_;

    return $underlying->pipsized_value($supplied_barrier) if $supplied_barrier =~ /^\d+(?:\.\d{0,12})?$/;

    my ($string, $pips);
    if ($supplied_barrier =~ /^S([-+]?\d+)P$/) {
        $pips = $1;
    } elsif ($supplied_barrier =~ /^[+-](?:\d+\.?\d{0,12})$/) {
        $pips = $supplied_barrier / $underlying->pip_size;
    } else {
        die "Unrecognized supplied barrier [$supplied_barrier]";
    }

    return [$LONGCODES->{entry_spot}] if abs($pips) == 0;

    if ($underlying->market eq 'forex') {
        $string = $pips > 0 ? $LONGCODES->{entry_spot_plus_plural} : $LONGCODES->{entry_spot_minus_plural};
        # taking the absolute value of $pips because the sign will be taken care of in the $string, e.g. entry spot plus/minus $pips.
        $pips = abs($pips);
    } else {
        $string = $pips > 0 ? $LONGCODES->{entry_spot_plus} : $LONGCODES->{entry_spot_minus};
        # $pips is multiplied by pip size to convert it back to a relative value, e.g. entry spot plus/minus 0.001.
        $pips *= $underlying->pip_size;
        $pips = $underlying->pipsized_value(abs($pips));
    }

    return [$string, $pips];
}

sub _strike_string {
    my ($string, $underlying_symbol, $contract_type_code) = @_;

    # do not use create_underlying because this is going to be very slow due to dependency on chronicle.
    my $underlying = Finance::Underlying->by_symbol($underlying_symbol);
    my $market     = Finance::Asset::Market::Registry->instance->get($underlying->market);

    $string /= FOREX_BARRIER_MULTIPLIER
        if ($contract_type_code !~ /^DIGIT/ and $string and looks_like_number($string) and $market->absolute_barrier_multiplier);

    return $string;
}

1;
