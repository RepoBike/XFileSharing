package Engine::Actions::PaymentComplete;
use strict;

use XFileConfig;
use Engine::Core::Action;

use URI::Escape;

sub main
{
   my ($str) = $ENV{QUERY_STRING}=~/payment_complete=(.+)/;
   my ( $id, $usr_id ) = split( /-/, uri_unescape($str) );
   ( $id, $usr_id ) = split( /-/, $ses->getCookie('transaction_id') ) if !$id;
   my $trans = $db->SelectRow(
      "SELECT *, INET_NTOA(ip) as ip, (UNIX_TIMESTAMP()-UNIX_TIMESTAMP(created)) as dt
                               FROM Transactions 
                               WHERE id=?", $id
   ) if $id;
   return $ses->message($ses->{lang}->{lang_no_transaction}) unless $trans;
   return $ses->message($ses->{lang}->{lang_internal_error}) unless $trans->{ip} eq $ses->getIP;
   return $ses->message($ses->{lang}->{lang_account_created_sucessfully})
     if $trans->{dt} > 3600;
   return $ses->message($ses->{lang}->{lang_payment_not_verified})
     unless $trans->{verified};

   my $user = $db->SelectRow(
      "SELECT *, UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as exp_sec 
                              FROM Users 
                              WHERE usr_id=?", $trans->{usr_id}
   );
   require Time::Elapsed;
   my $et  = new Time::Elapsed;
   my $exp = $et->convert( $user->{exp_sec} );
   $ses->PrintTemplate(
      'message.html',
      err_title => 'Payment completed',
      msg =>
"Your payment processed successfully!<br>You should receive your password on e-mail in few minutes.<br><br>Login: $user->{usr_login}<br>Password: ******<br><br>Your premium account expires in:<br>$exp",
   );
}

1;
