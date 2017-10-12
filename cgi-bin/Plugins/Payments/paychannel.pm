package Plugins::Payments::paychannel;
use Payments;
use base 'Payments';
use MIME::Base64;
use Digest::MD5 qw(md5);
use vars qw($ses $c);
use strict;

sub options
{
   return
   {
      name=>'paychannel', title=>'paychannel', account_field=>'paychannel_merchant_id', image=>'buy_paychannel.png', 
      listed_reseller=>'1',
      s_fields=>[
         {title=>'Your PayChannel Merchant ID', name=>'paychannel_merchant_id', type=>'text',size=>15},
         {title=>'Your PayChannel Secret Key', name=>'paychannel_secret', type=>'text', size=>30},
         ]
   };
}

sub checkout
{
   my ($self, $f) = @_;
   return if $f->{type} ne 'paychannel';

   my $plans = $ses->ParsePlans($c->{payment_plans}, 'hash');
   my $days = $f->{days}||$plans->{$f->{amount}};

   my $currency = iso4217($c->{currency_code});
   die("Unsupported currency: $c->{currency_code}") if !$currency;

   my $payment_descr = "$c->{site_name} $days days premium account";
   my $success_url = "$c->{site_url}/?payment_complete=$f->{id}-1";
   my $fail_url = "$c->{site_url}/?op=payments";
   
   my @payload = ($currency, $payment_descr, $fail_url, $c->{paychannel_merchant_id}, $f->{amount}, $f->{id}, $success_url);
   my $sign = encode_base64(sign(\@payload, $c->{paychannel_secret}), '');

   print "Content-type: text/html\n\n";
   print <<BLOCK
<HTML><BODY onLoad="document.F1.submit();">
<form name="F1" method="POST" action="https://payment.paychannel.cc/">
 <input type="hidden" name="RDI_MERCHANT_ID" value="$c->{paychannel_merchant_id}">
 <input type="hidden" name="RDI_PAYMENT_AMOUNT" value="$f->{amount}">
 <input type="hidden" name="RDI_CURRENCY_ID" value="$currency">
 <input type="hidden" name="RDI_PAYMENT_NO" value="$f->{id}">
 <input type="hidden" name="RDI_DESCRIPTION" value="$payment_descr">
 <input type="hidden" name="RDI_SUCCESS_URL" value="$success_url">
 <input type="hidden" name="RDI_FAIL_URL" value="$fail_url">
 <input type="hidden" name="RDI_SIGNATURE" value="$sign">
 <input type="submit" value="Redirecting...">
</form>
</BODY></HTML>
BLOCK
   ;
}

sub sign
{
   my ($field_values, $secret) = @_;
   return md5(join('', @$field_values) . $secret);
}

sub iso4217
{
   my ($currency_code) = @_;
   return {'USD' => 840, 'EUR' => 978}->{uc($currency_code)};
}

sub error
{
   print STDERR "$_[0]\n";
   print "Content-type: text/plain\n\nRDI_RESULT=OK";
   exit;
}

sub retry
{
   print STDERR "$_[0]\n";
   print "Content-type: text/plain\n\nRDI_RESULT=RETRY&RDI_DESCRIPTION=$_[0]";
   exit;
}

sub verify
{
   my ($self, $f) = @_;
   return if !$f->{RDI_MERCHANT_ID};
   my $transaction = $ses->db->SelectRow("SELECT * FROM Transactions WHERE id=?",$f->{RDI_PAYMENT_NO}) || error( "Transaction not found: '$f->{RDI_PAYMENT_NO}'"  );
   error("Already verified") if $transaction->{verified};

   my @keys = sort(grep { $_ ne 'RDI_SIGNATURE' } keys(%$f));
   my $sign = sign([ map { $f->{$_} } @keys ], $c->{paychannel_secret});

   retry("Wrong signature") if $sign ne decode_base64($f->{RDI_SIGNATURE});
   retry("Wrong status") if lc($f->{RDI_ORDER_STATE}) ne 'accepted';
   retry("Wrong amount") if $f->{RDI_PAYMENT_AMOUNT} != $transaction->{amount};
   retry("Wrong currency") if $f->{RDI_CURRENCY_ID} != iso4217($c->{currency_code});

   $f->{out} = "RDI_RESULT=OK";
   return($transaction);
}

1;
