#!/bin/perl
use strict;
use warnings;
use Data::Dumper;
use Getopt::Long;
use POSIX qw(ceil :sys_wait_h);
use Scalar::Util qw(looks_like_number);
use IO::Select;
#use Forks::Super;
use Term::ANSIColor;
use IPC::Open2;
use lib (qw(. /home/robin/perl5/lib/perl5/));
use Fcntl qw< LOCK_EX SEEK_END >;
use IO::Handle;

our $grid_max_rows = 20;
our $grid_active = 0;
our $grid_max = 0;
our (%window_param,@childs, @dead, $focused, $menu, @grid, $window, $chordui, $statusbar, $statsbar, $ui, $h, $w);
our ($menu_start, $menu_h, $grid_start, $grid_h, $grid_w,$statusbar_start,$statusbar_h,$statsbar_start,$statsbar_h);
our $finished = 0;
#use bignum;
my $nodes;
my @addr;
my @nodepid;
my @nodeout;
my $sleep = 10;

my $kill;
my $spawn;
my $max_h = 50;
my $max;
my $interactive;
my $ret = 0;
my $verbose;
our $overlay = 0;
our $header = 0;
our $auto = 0;
our $p = 0;
open(our $csvfh, '>', 'report.csv');
GetOptions(
	"nodes=i" => \$nodes,    # numeric
	"kill=i"   => \$kill,      # numeric
	"max=i"   => \$max,      # numeric
	"spawn=i"   => \$spawn,      # numeric
	"interactive"   => \$interactive,      # numeric
	"verbose"  => \$verbose
  )   # flag
  or die("Error in command line arguments\n");
if(!defined $nodes) {
	$nodes = 3;
}
chomp(our $lo = `ip -o link show | awk '/^([0-9]+):\\s([a-zA-Z0-9]+).+loopback.+\$/{print \$2}' | tr -d ':'`);
if($lo eq "") {
	print "No Loopback Interface found\n";
	exit(1);
}
my $end = 0;
$SIG{INT}  = sub { $end++ };

our $debug = '';
use Curses qw(KEY_ENTER);
if($interactive) {
	$SIG{ WINCH } = \ &winch;
	while(1) {
		setup_curses();
		$ui->mainloop();
	}
	$ui->DESTROY();
	print "\033[2J";    #clear the screen
	print "\033[0;0H"; #jump to 0,0
	print $debug;
} else {
	start_nodes($nodes,$lo,1,0);
	my $c = 0;
	while($end == 0) {
		sleep 1;
		if($end > 0){
			last;
		}
		my $not_in_sync = check_ring();
		$c++;
		if($verbose) {
			print Dumper(@childs);
			if(defined($max)) {
				print "Run $c/$max sync: $not_in_sync end: $end\n";
			}else {
				print "Run $c sync: $not_in_sync end: $end\n";
			}
		}
		if(defined($max) && $c == $max) {
			$ret = $not_in_sync;
			last
		}
		if($not_in_sync == 0 || $end > 0){
			if(!defined($kill)) {
				print "Ring in sync\n";
				check_utilization();
				#last;
			} else {
				print "Ring in sync\n";
				if(@childs == 1) {
					#last;
				}
			}
		} else {
			print "Not in sync yet\n";
		}
		if(defined($kill) && ($c % $kill) == 0 && @childs > 1) {
			my $victim = rand(@childs);
			$childs[$victim]{killed} = 1;
			print "Kill $childs[$victim]{cmd} with pid  $childs[$victim]{pid}\n";
			system("kill $childs[$victim]{pid}");
			splice(@childs,$victim,1);
		}
	}
}
		print "\033[2J";    #clear the screen
		print "\033[0;0H"; #jump to 0,0
	print $debug;

kill_nodes();
exit($ret);

sub winch {
	curses_restart();
}

sub setup_curses {
	$ui = new Curses::UI ( 
    	-color_support => 1,
    	-clear_on_exit => 1, 
    	-debug => $debug,
	);
	$h = $ui->height;
	$w = $ui->width;
	if($h < $max_h) {
		$ui->DESTROY();
		print "\033[2J";    #clear the screen
		print "\033[0;0H"; #jump to 0,0

		print "Screen to small need at least height of 30 got $h\n";
		exit 0;
	}
	$menu_start = 0;
	$menu_h = 1;
	$statusbar_start = 1;
	$statusbar_h = 1;
	$statsbar_start = 39;
	$statsbar_h = $h-$statsbar_start;
	$grid_start = 2;
	$grid_h = $statsbar_start-2;
	$grid_w = $w - 2;
	$ui->set_timer( 'std_periodic', \&periodic , 2);
	use Curses::UI;

    add_keybindings($ui);
	add_keybindings_generic();
	$window = $ui->add(
	  'window1', 'Window',
	  -border => 1,
	);

	add_statusbar();
	add_statsbar();
	add_menu();
	add_grid();
	focus_wrapper('menu');
}

sub add_grid {
	$grid_active = $grid_max;
	$grid_max++;
	push(@grid,{});
	$grid[$grid_active]{grid} = $window->add(
        "grid$grid_active",
        'Grid',
		-y 			  => $grid_start,
        -height       => $grid_h,
        -width        => $grid_w,
        -editable     => 0,
        -border       => 1,
		#-rows         => 20,
        # -fg       => "white",
    );
	$grid[$grid_active]{grid}->set_binding(\&dump_child, KEY_ENTER());
	$grid[$grid_active]{grid}->set_binding(\&curses_kill_child, 'd');
	for(my $i = 1;$i<=1;$i++) {
		$grid[$grid_active]{grid}->add_row("row$i");
	}
    $grid[$grid_active]{grid}->add_cell(
        "node_id",
        -width => 5,
        -label => "ID"
    );

	$grid[$grid_active]{grid} ->add_cell(
        "last_update",
        -width => 12,
        -label => "Time"
    );

    $grid[$grid_active]{grid} ->add_cell(
        "node_ip",
        -width => 10,
        -label => "Node IP"
    );

    $grid[$grid_active]{grid} ->add_cell(
        "master",
        -width => 10,
        -label => "Node Master"
    );

    $grid[$grid_active]{grid}->add_cell(
        "pid",
        -width => 10,
        -label => "Node PID"
    );
	$grid[$grid_active]{grid}->add_cell(
        "interface",
        -width => 5,
        -label => "If"
    );

	$grid[$grid_active]{grid}->add_cell(
        "predecessor",
        -width => 6,
        -label => "Pre"
    );
	$grid[$grid_active]{grid}->add_cell(
        "self",
        -width => 6,
        -label => "self"
    );

	$grid[$grid_active]{grid}->add_cell(
        "successor",
        -width => 6,
        -label => "Successor"
    );

	$grid[$grid_active]{grid}->add_cell(
        "read_b",
        -width => 15,
        -label => "read B/s"
    );

	$grid[$grid_active]{grid}->add_cell(
        "write_b",
        -width => 15,
        -label => "write B/s"
    );

	$grid[$grid_active]{grid}->add_cell(
        "overall_b",
        -width => 15,
        -label => "Overall B/s"
    );
	$grid[$grid_active]{grid}->add_cell(
        "w_user",
        -width => 15,
        -label => "wait user"
    );
	$grid[$grid_active]{grid}->add_cell(
        "w_sys",
        -width => 15,
        -label => "wait sys"
    );
	$grid[$grid_active]{grid}->add_cell(
        "p_user",
        -width => 15,
        -label => "periodic user"
    );
	$grid[$grid_active]{grid}->add_cell(
        "p_sys",
        -width => 15,
        -label => "periodic sys"
    );
	$grid[$grid_active]{grid}->add_cell(
        "share",
        -width => 10,
        -label => "Share"
    );
	$grid[$grid_active]{grid}->add_cell(
        "depth",
        -width => 10,
        -label => "Tree"
    );

	$grid[$grid_active]{row_count} = 1;
	$grid[$grid_active]{grid}->layout();
	update_statusbar();
}

sub next_grid {
	if($grid_active == $grid_max-1) {
		return;
	}
	$grid_active++;
	focus_wrapper("grid$grid_active");
	update_statusbar();
}

sub focus_wrapper {
	my ($f) = @_;
	$focused = $f;
	$window->focus($focused);
}
sub prev_grid {
	if($grid_active == 0) {
		return;
	}
	$grid_active--;
	focus_wrapper("grid$grid_active");
	update_statusbar();
}

sub add_menu {
	my @menu = (
	{ -label => 'New', 
		-submenu => [
				{ -label => '(a)dd Single node', -value => \&start_single_node  },
				{ -label => 'Multiple (N)odes', -value => \&start_nodes_curses  },
				{ -label => 'Coustom Nodes', -value => \&start_nodes_curses_custom  }
					]
	},
	{ -label => 'Util', 
		-submenu => [
				{ -label => 'Dump Node', -value => \&dump_child_question  },
				{ -label => 'Dump Ring', -value => \&curses_verbose  },
				{ -label => '(d)elete Selected Node', -value => \&curses_kill_child  },
				{ -label => '(k)ill Random Nodes', -value => \&kill_fraction  },
				{ -label => 'Ring (s)tatus', -value => \&dump_child_question  },
				{ -label => 'exit', -value => \&leave  },
				{ -label => 'restart', -value => \&curses_restart  },
				{ -label => '(t)oggle autostart', -value => \&auto_start  },
					]
	},
	{ -label => 'Grid', 
		-submenu => [
				{ -label => '(n)ext', -value => \&next_grid  },
				{ -label => '(p)previous', -value => \&prev_grid  },
					]
	},);
	$menu = $window->add(
        'menu','Menubar', 
        -menu => \@menu,
        -fg  => "blue",
		-y   => $menu_start,
		-height => $menu_h,
	);
}

sub kill_nodes {
	print "Kill\n";
	for(my $i = 0;$i<@childs;$i++) {
		if(defined($childs[$i])) {
			print "Kill: $childs[$i]{pid}\n";
			system("kill $childs[$i]{pid}");
		}
	}
}
sub add_keybindings {
	my ($target) = @_;
	$target->set_binding( sub{ my $count = $ui->question('How many?:'); if(defined ($count) && looks_like_number($count)) {start_nodes($count+0,$lo,1,1); } } , "a");
	$target->set_binding( sub{ start_nodes(1,$lo,0,1) } , "m");
	$target->set_binding( sub{ curses_ring_status() } , "s");
}

sub add_keybindings_generic {
	$ui->set_binding( sub{ leave(); } , "\cC");
	$ui->set_binding( sub{ move_focus(); } , "\t");
	$ui->set_binding( sub{ next_grid() } , "n");
	$ui->set_binding( sub{ prev_grid() } , "p");
	$ui->set_binding( sub{ curses_verbose() } , "v");
	$ui->set_binding( sub{ curses_restart() } , "f");
	$ui->set_binding( sub{ kill_fraction() } , "k");
	$ui->set_binding( sub{ auto_start() } , "t");
}

sub leave { kill_nodes(); exit; }

sub auto_start {
	if($auto == 0) {
		$auto = 1;
	} else {
		$auto = 0;
	}
}

sub kill_node {
	(my $count) = @_;
	for(my $i = 0;$i < $count;$i++) {
		my $victim = rand(@childs);
		$childs[$victim]{killed} = 1;
		print "Kill $childs[$victim]{cmd} with pid  $childs[$victim]{pid}\n";
		system("kill $childs[$victim]{pid}");
		splice(@childs,$victim,1);
	}
}


sub toggle_verbose {
	if($verbose) {
		print "Toggle Verbose off\n";
		$verbose = 0;
	} else {
		print "Toggle Verbose on\n";
		$verbose = 1;
	}
}

sub exit_dialog()
{
        my $return = $ui->dialog(
                -message   => "Do you really want to quit?",
                -title     => "Are you sure???", 
                -buttons   => ['yes', 'no'],
        );
exit(0) if $return;
}	

sub key_other {
	insert_row();
}
sub insert_row {
	start_single_node();
}
sub start_single_node()
{
   curses_start_nodes(1,$lo,0,0);
   my $return = $ui->dialog(
                -message   => "Amount: 1",
                -title     => "Nodes Started", 
                -buttons   => ['ok'],
	);
	return $return;
}

sub dump_child_question {
	my $return = $ui->question(
                -question   => "Whic one?"
	);
	if(looks_like_number($return) && $return > 0) {
		dump_child($return);
	}
	return $return;
}

sub dump_child {
$overlay = 1;
my $this = shift;
my %values = $grid[$grid_active]{grid}->get_foused_row()->get_values();
my $str = Dumper(\%values);
if(!(exists $values{node_id} && defined $values{node_id} && length($values{node_id})>1 )) {
	return;
}
my $id = int(substr($values{node_id},1,length($values{node_id})))-1;
if($id >= 0) {
	$str = Dumper(sort($childs[$id]));
} else {
	return;
}
		my $return = $ui->dialog(
                -message   => "$str",
                -title     => "Nodes Started", 
                -buttons   => ['ok'],
	);
	$overlay = 0;
}


sub curses_restart {
	$ui->layout_new();
}

sub kill_fraction {
	my $return = $ui->question(
                -question   => "How Many?"
	);
	if(looks_like_number($return) && $return > 0) {
		my @victims = [];
		for(my $i = 0;$i<$return;$i++) {
			my $already_victimized = 0;
			my $rnd_kill = int(rand @childs);
			kill_child($rnd_kill);
			
		}
	}
	return 0;
}

sub curses_kill_child {
	my $this = shift;

	my %values = $grid[$grid_active]{grid}->get_foused_row()->get_values();
	my $str = Dumper(\%values);
	if(!(exists $values{node_id} && defined $values{node_id} && length($values{node_id})>1 )) {
		return;
	}
	my $id = int(substr($values{node_id},1,length($values{node_id})))-1;
	if($id < 0) {
		return;
	}
	$id = ($grid_active*$grid_max_rows)+$id;
	my $return = $ui->dialog(
                -message   => "Do you really want to kill $id?",
                -title     => "Are you sure???", 
                -buttons   => ['yes', 'no'],
	);
	if($return) {
		kill_child($id);
	}
}

sub kill_child() {
	my ($id) = @_;
	if(defined($childs[$id])) {
		my $row = $childs[$id]{row};
		my $gridnr = $childs[$id]{gridnr};
		my $rownr  = $childs[$id]{rownr};
		my $g = $grid[$gridnr]{grid}{-rowid2idx};
		my $position = $g->{$row->{-id}};
		print STDERR "Kill node $id " . $childs[$id]{me} . " grid $gridnr row: $rownr pos: $position\n";
		system("kill " . $childs[$id]{pid});
		if(defined $row) {
			if(defined $position) {
				$grid[$gridnr]{grid}->delete_row($position);
			}
			else {
				$grid[$gridnr]{grid}->delete_row($position);
			}

		} else {
			my $max = $grid[$childs[$id]{gridnr}]{grid}->rows_count;
			print STDERR "Grid $gridnr row $rownr not defined grows: $max\n";
		}
		print STDERR "splice $id\n";
		splice(@childs, $id, 1);
		periodic();
	}
}

sub periodic {
	my $start = time();
	if(($start-$finished) < 5 || $overlay) {
		return;
	}
	my $nodes_exists = @childs;
	#$chordui->draw();
	update_nodes();
	update_pointer();
	ring_sort();
	for(my $i = 0;$i<$nodes_exists;$i++) {
		my $rownr  = $childs[$i]{rownr};
		my $s = '';
		my $p = '';
		my $t = '';
		my $self = '';
		my $read_b = 0;
		my $write_b = 0;
		my $overall_b = 0;
		my $puser = 0;
		my $psys = 0;
		my $wuser = 0;
		my $wsys = 0;
		my $share = 0;
		my $depth = 0;
		if(defined $childs[$i]{details} && ref($childs[$i]{details}) eq 'HASH') {
			if(defined $childs[$i]{details}{suc}) {
				$s = $childs[$i]{details}{suc};
			}
			if(defined $childs[$i]{details}{pre}) {
				$p = $childs[$i]{details}{pre};
			}
			if(defined $childs[$i]{details}{time}) {
				$t = $childs[$i]{details}{time};
			}
			if(defined $childs[$i]{details}{me}) {
				$self = $childs[$i]{details}{me};
			}
			if(defined $childs[$i]{details}{read_b}) {
				my $duration = 1;
				if($childs[$i]{details}{duration} > 0) {
					$duration = $childs[$i]{details}{duration};
				}
				$overall_b = sprintf("%.2f B/s", ($childs[$i]{details}{read_b}+$childs[$i]{details}{write_b})/$duration);
				$read_b = sprintf("%.2f B/s", $childs[$i]{details}{read_b}/$duration);
				$write_b = sprintf("%.2f B/s",$childs[$i]{details}{write_b}/$duration);
			}
			if(defined $childs[$i]{details}{wait_cpu_u}) {
				my $cpns =  0;
				if($childs[$i]{details}{wait_elapsed} != 0) {
					$cpns = ($childs[$i]{details}{wait_cpu_u}/$childs[$i]{details}{wait_elapsed})*1000000000;
				}
				$wuser = sprintf("%d %.2f C/s",$childs[$i]{details}{wait_cpu_u}, $cpns);
			}
			if(defined $childs[$i]{details}{wait_cpu_s}) {
				my $cpns =  0;
				if($childs[$i]{details}{wait_elapsed} != 0) {
					$cpns = ($childs[$i]{details}{wait_cpu_s}/$childs[$i]{details}{wait_elapsed})*1000000000;
				}
				$wsys = sprintf("%d %.2f C/s",$childs[$i]{details}{wait_cpu_s}, $cpns);
			}
			if(defined $childs[$i]{details}{periodic_cpu_u}) {
				my $cpns =  0;
				if($childs[$i]{details}{wait_elapsed} != 0) {
					$cpns = ($childs[$i]{details}{periodic_cpu_u}/$childs[$i]{details}{wait_elapsed})*1000000000;
				}
				$puser = sprintf("%d %.2f C/s",$childs[$i]{details}{periodic_cpu_u}, $cpns);
			}
			if(defined $childs[$i]{details}{periodic_cpu_s}) {
				my $cpns =  0;
				if($childs[$i]{details}{wait_elapsed} != 0) {
					$cpns = ($childs[$i]{details}{periodic_cpu_s}/$childs[$i]{details}{wait_elapsed})*1000000000;
				}
				$psys = sprintf("%d %.2f C/s",$childs[$i]{details}{periodic_cpu_s}, $cpns);
			}
			if(defined $childs[$i]{details}{share}) {
				$share = $childs[$i]{details}{share};
			}
			if(defined $childs[$i]{details}{depth}) {
				$depth = int($childs[$i]{details}{depth});
			}
		}
		my $target = int($i/$grid_max_rows);
		my $real_pos = ($i % $grid_max_rows)+1;
		$childs[$i]{gridnr} = $target;
		$childs[$i]{rownr}  = $real_pos;
		if($target == $grid_max) {
			add_grid();
		}
		if( not defined $grid[$target]{grid}->get_row("row$real_pos")) {
			$childs[$i]{row} = $grid[$target]{grid}->add_row(
            "row$real_pos",
            # -fg    => 'black',
            # -bg    => 'yellow',
            -cells => {
				last_update => $t,
                node_id     => "#$real_pos",
                node_ip => $childs[$i]{addr},
                master    => $childs[$i]{master_addr},
                pid => $childs[$i]{pid},
                successor => $s,
                self => $self,
                predecessor => $p,
				interface => $childs[$i]{interface},
				read_b => $read_b,
				write_b => $write_b,
				overall_b => $overall_b,
				p_user => $puser,
				p_sys  => $psys,
				w_user => $wuser,
				w_sys  => $wsys,
				share  => $share,
				depth  => $depth,
				debug =>$debug,
            }
			);
			$grid[$target]{row_count}++;
		} else {
 			$grid[$target]{grid}->set_values("row$real_pos",
								node_id 	=> "#$real_pos",
								node_ip 	=> $childs[$i]{addr},
								master 		=> $childs[$i]{master_addr},
								pid 		=> $childs[$i]{pid},
								interface 	=> $childs[$i]{interface},
								successor	=> $s,
								self 		=> $self,
								predecessor => $p,
								last_update => $t,
								read_b 		=> $read_b,
								write_b 	=> $write_b,
								overall_b 	=> $overall_b,
								p_user 		=> $puser,
								p_sys  		=> $psys,
								w_user 		=> $wuser,
								w_sys  		=> $wsys,
								share 	 	=> $share,
								depth 	 	=> $depth,
								debug    	=> $debug,
								);
			$childs[$i]{row} = $grid[$target]{grid}->get_row("row$real_pos");
		}
	}
	update_statusbar();
	update_statsbar();
	$finished = time();
	my $run = $finished-$start;
	$p++;
	if($auto == 1 && $p % 5 == 0) {
		start_nodes(1,$lo,0,1);
	}
	return 0;
}

sub add_statusbar {
	$statusbar = $window->add(
		'statusbar', 'Label',
		-text   => get_statusbar(),
		-bold   => 1,
		-width 	=> $w,
		-y      => $statusbar_start,
		-height => $statusbar_h,
		-bbg    => "white",
		-focusable => 0,

	);
}

sub add_statsbar {
	$statsbar = $window->add(
		'statsbar', 'Label',
		-text   => "under construction",
		-bold   => 1,
		-width 	=> $w,
		-y      => $statsbar_start,
		-height => $statsbar_h,
		-x      => 1,
		-bbg => "white",
		-bfg => "white",
		-focusable => 0,
	);
}

sub update_statsbar {
	$statsbar->text(get_statsbar());
	$statsbar->draw();
}

sub get_statsbar {
	my %results;
	my %count;
	my $str = '';
	my $csv = @childs . ',';
	my $h = 'nodes,';
	my $min_share = 9999999;
	my $max_depth = 0;
	my $max_share = 0;
	for (my $i = 0;$i<@childs;$i++) {
		if(defined $childs[$i]{details}) {
			if(defined $childs[$i]{details}{share} && $childs[$i]{details}{share} != 0) {
				if($childs[$i]{details}{share} > $max_share) {
					$max_share = $childs[$i]{details}{share};
				}
				if($childs[$i]{details}{share} < $min_share) {
					$min_share = $childs[$i]{details}{share};
				}
			}
			if(defined $childs[$i]{details}{depth} && $childs[$i]{details}{depth} != 0) {
				if($childs[$i]{details}{depth} > $max_depth) {
					$max_depth = $childs[$i]{details}{depth};
				}
			}
			foreach my $key (keys %{$childs[$i]{details}})
			{
				if($childs[$i]{details}{$key} eq 'NULL') {
					next;
				}
				if(!defined $results{$key}) {
					$results{$key} = $childs[$i]{details}{$key};
					$count{$key} = 1;
				} else {
					$results{$key} += $childs[$i]{details}{$key};
					$count{$key}++;
				}
			}
		}
	}
	if(@childs == 0 || keys %results == 0) {
		return '';
	}

	$results{min_share} = $min_share;
	$count{min_share} = 1;
	$results{max_share} = $max_share;
	$count{max_share} = 1;
	$results{max_depth} = $max_depth;
	$count{max_depth} = 1;
	my $size = keys %results;
	my $kpl = int(($size/$statsbar_h))+1;

	my $i = 0;
	foreach my $key (sort keys %results)
	{
		if($i == $kpl) {
			$i = 0;
			$str .= "\n";
		}
		my $value = $results{$key};
		my $count = $count{$key};
		$str .= "$key: " . $value/$count;
		$csv .= $value/$count . ",";
		if($header == 0) {
			$h .= "$key,";
		}
		if($i != $kpl-1) {
			$str .= ' | ';
		}
		$i++;
	}
	if($header == 0) {
		$h .= "\n";
		print $csvfh $h;
		$header = 1;
	}
	$csv .= "\n";
	print $csvfh $csv;
	$csvfh->flush();
	return $str;
}

sub update_statusbar {
	$statusbar->text(get_statusbar());
	$statusbar->draw();
}

sub get_statusbar {
	my $nr = @childs;
	my $a = ($grid_active+1);
	my $status = "Active Grid $a/$grid_max. #$nr childs active";
	if(defined $ui && defined $ui->width) {
		my $w = $ui->width;
		$status .= " w: $w"
	}
	if(defined $ui && defined $ui->height) {
		my $h = $ui->height;
		$status .= " h: $h"
	}
	return $status;
}
sub start_nodes_curses_custom {
	return curses_get_node_number();
}

sub start_nodes_curses {
	return curses_get_node_number();
}

sub curses_get_node_number {
		my $return = $ui->question(
                -question   => "How Many?"
	);
	if(looks_like_number($return) && $return > 0) {
		$nodes = $return;
		$return = $ui->dialog(
					-message   => "Amount: $return",
					-title     => "Nodes Started", 
					-buttons   => ['ok'],
		);
		curses_start_nodes($nodes,$lo,0,1);
	} else {
		$return = $ui->dialog(
					-message   => "NaN",
					-title     => "Error", 
					-buttons   => ['ok'],
		);
	}
	return $return;
}
sub curses_start_nodes {
	(my $count, my $interface, my $sleep, my $silent) = @_;
	start_nodes($count,$interface,$sleep,$silent);
	periodic();

}
sub start_nodes {
	(my $count, my $interface, my $sleep, my $silent) = @_;
	$verbose = 0;
	#print "Start with $count nodes on interface $interface\n";
	my $nodes_exists = @childs;
	if($count > 1) {
		$ui->progress(
   	 		-max => $count,
    		-message => "Starting $count nodes...",
		);
	}
	for(my $i = 0;$i<$count && $end == 0;$i++) {
		if($count > 1) {
			$ui->setprogress($i);
		}
		my $id = $nodes_exists + $i;
		my $rnd_master_addr = '';
		my $hex = sprintf("%X", $id+1);
		$childs[$id]{addr} = "::$hex";
		$childs[$id]{me} = 0;
		if($id == 0) {
			$childs[$id]{master_addr} = $childs[$id]{addr};
		}
		$childs[$id]{interface} = "tap$id";
		if(not defined $childs[$id]{master_addr}) {
			while(1) {
				my $rnd_master = rand @childs;
				if(defined $childs[$rnd_master] && defined $childs[$rnd_master]{starttime} && (time()-$childs[$rnd_master]{starttime}) > 4) {
					$rnd_master_addr =  $childs[$rnd_master]{addr};
					last;
				}
				sleep(1);
			}
			$childs[$id]{master_addr} = $rnd_master_addr;
		}

		system("sudo ifconfig $interface inet6 add $childs[$id]{addr} > /dev/null 2>&1");
		$childs[$id]{killed}  = undef;
		$childs[$id]{buffer} = [];
		#$childs[$id]{rbuffer} = new RingBuffer(Buffer            => $childs[$id]{buffer},
#											   RingSize          => 10,
#											   Overwrite         => 1,#
#											    PrintExtendedInfo => 0,
#											  );
		#$childs[$id]{rbuffer}->ring_init();
		$childs[$id]{cmd} = "";
		if($id == 0) {
			$childs[$id]{cmd} = "./example master $childs[$id]{addr} silent";
		} else {
			$childs[$id]{cmd} = "./example slave $childs[$id]{addr} $rnd_master_addr silent";
		}
		$childs[$id]{starttime} = time();
		if($verbose) {
			print "$childs[$id]{cmd}\n";
		}
		#$childs[$id]{pid}  = fork{ exec => $childs[$id]{cmd},
		#						   child_fh => "all" };
		my $cmd = $childs[$id]{cmd};
		if ($childs[$id]{pid}  = open($childs[$id]{out} , "$cmd|")) {
			$childs[$id]{out}->autoflush(1);
			$childs[$id]{out}->blocking(0);
			my $fh = $childs[$id]{out};

 		} else {
			 close(STDIN);
			#exec($childs[$id]{cmd});
		}


		if($sleep > 0) {
			sleep($sleep);
		}
	}
	$ui->noprogress;
}


sub ring_to_str {
	ring_sort();
	my $str = "";
	for(my $i = 0;$i<@childs;$i++) {
		$str .= $childs[$i]{me};
		if($i != @childs-1) {
			$str .=  "->";
		}
	}
	return $str;
}


sub ring_sort {
	@childs =  sort { (defined($a->{me}) <=> defined($b->{me})) || $a->{me} <=> $b->{me} } @childs;
}

sub check_utilization {
	my $ring_size = 2**16;
	for(my $i = 0;$i<@childs;$i++) {
		my $me = $childs[$i]{me};
		my $pre = $childs[$i]{state}{$me}{pre};
		my $diff = 0;
		if($me < $pre) {
			$diff = $ring_size-$pre + $me;
		} else {
			$diff = $me-$pre;
		}
		my $percentage = (100/$ring_size) * $diff;
		print "$me is responsilbe for $percentage% of the Ring\n"
	}
}

sub curses_verbose() {
	my $dump = Dumper(@childs);
	   my $return = $ui->dialog(
                -message   => "$dump",
                -title     => "Dump Ring", 
                -buttons   => ['ok'],
	);
	return $return;
}

sub curses_ring_status() {
	my $details = '';

	my $in_sync = check_ring(\$details);
	   my $return = $ui->dialog(
                -message   => "Ring Sync Errors: $in_sync",
                -title     => "Ring Sync Check", 
                -buttons   => ['no','yes'],
	);
	if($return == 1) {
      	$return = $ui->dialog(
                -message   => $details,
                -title     => "Ring Sync Details", 
                -buttons   => ['ok'],
		);
	} else {
		print $return;
	}
	return $return;
}
sub update_pointer() {
	for(my $i = 0;$i<@childs;$i++) {
		my $fh = $childs[$i]{out};
		if(!defined $fh) {
			print STDERR "fh of $i is not defined\n";
		}
		my @line;
		my $tell = tell($fh);
		while (my $line = <$fh>)
		{
			$tell = $line;
		}
		$childs[$i]{last} = $tell;

		if(defined $childs[$i]{last} && ($childs[$i]{last} =~ /(.+:.+\|*)/)) {
			my %details = split /[|:]/, $childs[$i]{last};
			#$childs[$i]{rbuffer}->ring_add(\%details);
			$childs[$i]{details} =  \%details;
			#$childs[$i]{details} = "wasd";
			if(defined $childs[$i]{details}{me}) {
				$childs[$i]{me} = $childs[$i]{details}{me};
			}
		}
	}
}

sub update_nodes() {
	return 0;
}

sub check_ring {
	my ($details) = @_;
	update_nodes();
	update_pointer();
	ring_sort();
	my $not_in_sync = 0;
	my $err = '';
	my $last = @childs;
	my @c = @childs;
	for(my $i = 0;$i<@c;$i++) {
		my $real_pre = -1;
		my $real_suc = -1;
		my $me = $c[$i]{me};
		my $suc = 0;
		if(defined $c[$i]{details}{suc}) {
			$suc = $c[$i]{details}{suc};
		}
		my $pre = 0;
		if(defined  $c[$i]{details}{pre}) {
			$pre =  $c[$i]{details}{pre};
		}
		if($i == $last-1) {
			if (defined( $c[0]{details}{me})) {
				$real_suc =  $c[0]{details}{me};
			}
		}else {
			if(defined $c[$i+1]{details}{me}) {
				$real_suc = $c[$i+1]{details}{me};
			}
		}
		if($i == 0) {
			if(defined $c[$last-1]{details}{me}){
				$real_pre = $c[$last-1]{details}{me};
			}
		}else {
			if(defined $c[$i-1]{details}{me}){
				$real_pre = $c[$i-1]{details}{me};
			}
		}

		if($pre eq 'NULL' || $pre != $real_pre) {
			$not_in_sync++;
			my $n = -1;
			if(defined  $c[$i]{details}{me}) {
				$n = $c[$i]{details}{me}
			}
			$err .= "Error Node " . $n. " expects pre $real_pre but got $pre in output\n";
		}
		if($suc != $real_suc) {
			$not_in_sync++;
			my $n = -1;
			if(defined  $c[$i]{details}{me}) {
				$n = $c[$i]{details}{me}
			}
			$err .= "Error Node " . $n ." expects suc $real_suc but got $suc in output\n";
		}
	}
	if($err eq '') {
		$err .= 'Everything fine!';
	}
	if(defined $details) {
		$$details = $err;
	}
	return $not_in_sync;
}

sub move_focus {
	if($focused eq "grid$grid_active") {
		focus_wrapper('menu');
	} else {
		focus_wrapper("grid$grid_active");
	}
}




sub print_help {

	my $bold =  color('bold');
	my $normal = color('reset');
	print "commands:\n";
	print "${bold}start_node:${normal}\tStart one node\n";
	print "${bold}s:${normal}\t\tStart one node\n";
	print "${bold}start_node n t:${normal}\tStart n nodes with t seconds pause in between spawn\n";
	print "${bold}status:${normal}\t\tPrint Ring status\n";
	print "${bold}verbose:${normal}\tToggle verbose mode\n";
	print "${bold}kill n:${normal}\t\tKill n random nodes\n";
	print "${bold}kill:${normal}\t\tKill one node\n";
	print "${bold}k:${normal}\t\tKill one node\n";
}
