use ExtUtils::MakeMaker;

WriteMakefile(
	NAME         => 'Net::RTSP',
	VERSION_FROM => 'lib/Net/RTSP.pm',
	PREREQ_PM    => {},
		(($] >= 5.005)
			? (ABSTRACT_FROM => 'lib/Net/RTSP.pm',
			   AUTHOR        => 'William G. Davis ' .
			                    '<william_g_davis@users.' .
					    'sourceforge.net>')
			: ()
		)
);
