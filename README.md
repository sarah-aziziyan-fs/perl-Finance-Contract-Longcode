# NAME

Finance::Contract::Longcode - contains utility functions to convert a binary.com's shortcode to human readable longcode and shortcode to a hash reference parameters.

# SYNOPSIS

    use Finance::Contract::Longcode qw(shortcode_to_longcode);

    my $longcode = shortcode_to_longcode('PUT_FRXEURNOK_100_1394590423_1394591143_S0P_0','USD');

# DESCRIPTION

Shortcode is a string representation of a binary.com's contract. An example of shortcode would be 'CALL\_FRXUSDJPY\_100\_1393816299\_1393828299\_S0P\_0' where each contract parameter is separated by an underscore.

In the example above:

\- CALL is a binary.com's contract type
\- FRXUSDJPY is a binary.com's symbol for an financial instrument
\- 100 is the payout of the contract
\- 1393816299 is the start time of the contract, in epoch.
\- 1393828299 is the expiration time of the contract, in epoch.
\- S0P is the first strike representation of the contract.
\- 0 is the second strike representation of the contract.

Longcode is the human readable representation of the shortcode. The longcode for the example above would be translated to 'Win payout if USD/JPY is strictly higher than entry spot at 12 minutes after contract start time'.

## get\_longcodes

Returns a hash reference of longcode related strings

## shortcode\_to\_longcode

Converts shortcode to human readable longcode. Requires a shortcode.

Returns an array reference of strings.

## shortcode\_to\_parameters

Converts shortcode to a hash reference parameters. Requires shortcode.

Optional parameters:

\- currency is provided if you wish to have a complete list of parameters to create a contract.
\- is\_sold is to indicate of a contract is sold.

Returns a hash reference.
