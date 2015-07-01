/* LPTEST.C -- Test/demo program for LPTCAP system - k@heidenstrom.gen.nz

KH.19961007.001  Started
KH.19971012.002  Updated for LPTCAP changes of this date
KH.19971013.003  Changed structure to command-driven (was fixed sequence)
KH.19971018.004  Updated for changed LPTCAP software module
KH.19971220.005  Release version - release 1
KH.20000204.006  Email address kheidens@clear.net.nz -> k@heidenstrom.gen.nz

Assemble the LPTCAP module first, then use the command line:

bcc -I<includepath> -K -L<libpath> -d -f- -ms -olptest -w lptcap-s.obj lptest.c
ren lptcap-s.exe lptest.exe

*/

#define LPTEST_REVISION 006
#define LPTEST_VERSION	1
#define LPTEST_SUBVER	0
#define LPTEST_MODVER	1
#define LPTEST_DATE	"20000402"

#define INTBUF_SIZE 1024

#include "lptcap.h"
#include <bios.h>
#include <ctype.h>
#include <dos.h>
#include <stdio.h>
#include <stdlib.h>

typedef union {
	unsigned int uint;
	struct {
		unsigned char lobyte;
		unsigned char hibyte;
		} bytes;
	} word_two_bytes;

static word_two_bytes test_error_data;

typedef union {
	unsigned long ulong;
	struct {
		unsigned int loword;
		unsigned int hiword;
		} words;
	} long_two_words;

static long_two_words lptcap_date;

static char * status_descriptions[] = {
	"OK",				/* LPTCAP_ADAPTER_PRESENT */
	"No parallel port",		/* LPTCAP_ADAPTER_NO_PORT */
	"Not attached",			/* LPTCAP_ADAPTER_MISSING */
	"Interrupt mode active",	/* LPTCAP_ADAPTER_INTMODE */
	"No DRDY indication",		/* LPTCAP_ADAPTER_NO_DRDY */
	"ACKP stuck active",		/* LPTCAP_ADAPTER_ACKSTUK */
	"No ACKP indication",		/* LPTCAP_ADAPTER_NO_DACK */
	"ACKP pulse too long",		/* LPTCAP_ADAPTER_ACKLONG */
	"BUSY latch set after ACK",	/* LPTCAP_ADAPTER_BSYSTUK */
	"STROBE stuck active",		/* LPTCAP_ADAPTER_STRSTUK */
	"SDI lines inconsistent",	/* LPTCAP_ADAPTER_SDISERR */
	"Data loopthrough error"	/* LPTCAP_ADAPTER_DATAERR */
	};

static int irq, statuses, intmode;

static lptcap_bufdescriptor bd;

static char input[128];		/* General line input buffer */

void * intbuf;			/* Pointer to buffer area */

static FILE * outfile;

unsigned int tick_changed(void) {
	static unsigned int lasttick;
	unsigned int tick;
	tick = * (unsigned int far *)MK_FP(0, 0x46C);
	if (tick != lasttick) {
		lasttick = tick;
		return 1;
		}
	return 0;
	}

char * make_printable(int c) {
	static char printable[20];	/* One static buffer for return value! */
	printable[0] = c;
	printable[1] = '\0';		/* Assume it will be printable */
	if ((c < ' ') || (c > 126))
		sprintf(printable, "0x%02X", c);
	return printable;
	}

void do_command(void) {
	unsigned int param, stat, oldins, newins, gotchar;
	int c, twirly;
	unsigned long charcounter;
	static char ind[] = "\xB3/\xC4\\";

	printf("\nCommand? ");
	c = bioskey(0) & 0xFF;
	if (c >= ' ')
		putchar(c);
	putchar('\n');

	switch (tolower(c)) {
	case 'h' :
	case '?' :
	case '\0' :
		printf("D\tDiagnostic\tPerform diagnostic test\n"
		       "A\tAdjustment\tGenerate adjustment signal\n"
		       "V\tView controls\tView control signals from Sender\n"
		       "S\tStatuses\tSet statuses to Sender\n"
		       "K\tSendack\t\tSend unsolicited acknowledgement\n"
		       "T\tTestNew\t\tTest whether data is pending\n"
		       "G\tGet\t\tGet and display one captured character\n"
		       "W\tWaitChar\tWait with ten second timeout for character\n"
		       "C\tCapture\t\tCapture to screen or disk file\n"
		       "I\tIntMode\t\tToggle interrupt / polled modes\n"
		       "Q\tQuit\t\tQuit LPTEST\n");
		return;
	case 'd' :		/* Diagnostic */
		printf("Enter number of test loops: ");
		gets(input);
		param = (unsigned int) atol(input);
		if (param) {
			printf("Testing for %u loop(s)... ", param);
			stat = lptcap_test(param);	/* Do it */
			if (stat)
				printf("\nResult: error %u, %s\n", stat, status_descriptions[stat]);
			else
				printf("\nResult: OK\n");
			if (stat == LPTCAP_ADAPTER_DATAERR) {
				test_error_data.uint = lptcap_test_fail_data();
				printf("\t\tData loopthrough failure: sent 0x%02X, read 0x%02X\n",
				test_error_data.bytes.lobyte,
				test_error_data.bytes.hibyte);
				}
			if ((stat == LPTCAP_ADAPTER_BSYSTUK) ||
			    (stat == LPTCAP_ADAPTER_STRSTUK))
				printf("\t\tNote - This could be because the Sender is trying to send data.\n"
				       "\t\t       The diagnostic test should be run with the Sender idle.");
			}
		return;
	case 'a' :		/* Adjustment signal */
		printf("Enter number of ticks (or zero for adjust until Ctrl pressed): ");
		gets(input);
		param = (unsigned int) atol(input);
		if (param)
			printf("Generating adjustment signal for %u ticks... ", param);
		else
			printf("Generating adjustment signal, press Ctrl to stop... ");
		lptcap_adjust(param);	/* Do adjustment */
		putchar('\n');
		while (bioskey(1)) bioskey(0);	/* Flush buffer */
		return;
	case 'v' :		/* View controls */
		printf("Displaying control signals from sender - press any key to stop\n");
		oldins = 0xFFFF;		/* Pre-set to a non-existent state */
		while (bioskey(1) == 0) {
			newins = lptcap_get_cont();
			if (newins != oldins) {
				oldins = newins;
				printf("SELECT = %c;   INITIALIZE = %c;   AUTOFEED = %c\n",
				(newins & LPTCAP_CONT_SELECT) ? 'Y' : 'N',
				(newins & LPTCAP_CONT_INITIALIZE) ? 'Y' : 'N',
				(newins & LPTCAP_CONT_AUTOFEED) ? 'Y' : 'N');
				}
			} /* end while() */
		bioskey(0);			/* Flush the keypress */
		return;
	case 's' :		/* Send statuses to Sender */
		for(;;) {
			printf("PAPER OUT = %c;  SELECTED = %c;  ERROR = %c\n",
				(statuses & LPTCAP_STAT_PAPEROUT) ? 'Y' : 'N',
				(statuses & LPTCAP_STAT_NOTSELECTED) ? 'N' : 'Y',
				(statuses & LPTCAP_STAT_ERROR) ? 'Y' : 'N');
			printf("\tChange:  [P]aperOut  [S]elected  [E]rror  [A]ll   [Q]uit? ");
			c = bioskey(0) & 0xFF;
			if (c >= ' ')
				putchar(c);
			putchar('\n');
			switch (tolower(c)) {
			case 'p' :
				statuses ^= LPTCAP_STAT_PAPEROUT;
				break;
			case 's' :
				statuses ^= LPTCAP_STAT_NOTSELECTED;
				break;
			case 'e' :
				statuses ^= LPTCAP_STAT_ERROR;
				break;
			case 'a' :
				statuses ^= (LPTCAP_STAT_PAPEROUT | LPTCAP_STAT_NOTSELECTED | LPTCAP_STAT_ERROR);
				break;
			case 'q' :
			case '\x1B' :
				return;
			default :
				break;
				}  /* end switch() */
			lptcap_set_stat(statuses);
			}
	case 'k' :			/* Send unsolicited acknowledgement */
		printf("Sending unsolicited acknowledgement\n");
		lptcap_send_ack();
		return;
	case 't' :			/* Test whether new data is pending */
		printf("New data %s pending\n", lptcap_poll_new() ? "is" : "is not");
		return;
	case 'g' :			/* Get and display captured character */
		c = lptcap_next_char();
		if (c == LPTCAP_NOCHAR)
			printf("New captured character: none available\n");
		else
			printf("New captured character: '%s'\n", make_printable(c));
		return;
	case 'w'  :			/* Wait with 10 second timeout for char */
		c = lptcap_wait_char(182);
		if (c == LPTCAP_NOCHAR)
			printf("Timeout - no character available\n");
		else
			printf("Captured character: '%s'\n", make_printable(c));
		return;
	case 'c' :			/* Capture to screen or disk file */
		printf("Enter name of capture file (or blank to capture to screen): ");
		gets(input);
		if (input[0] != 0) {
			outfile = fopen(input, "rb");	/* See if it's there */
			if (outfile != NULL) {
				fclose(outfile);
				outfile = NULL;
				printf("Output file '%s' already exists - append or overwrite (A/O)? ", input);
				if (tolower(bioskey(0) & 0xFF) != 'o') {
					printf("Append\n");
					outfile = fopen(input, "ab");
					}
				else
					printf("Overwrite\n");
				}
			if (outfile == NULL)
				outfile = fopen(input, "wb");
			if (outfile == NULL) {
				printf("Error - couldn't open capture file '%s'\n", input);
				return;
				}
			}
		if (outfile == NULL)
			printf("Now capturing to screen - press any key to stop\n");
		else
			printf("Now capturing to file '%s' - press any key to stop\n", input);
		gotchar = twirly = 0;
		charcounter = 0;
		while (bioskey(1) == 0) {
			if ((c = lptcap_next_char()) != LPTCAP_NOCHAR) {
				gotchar = 1;
				++charcounter;
				if (outfile == NULL)
					putchar(c);
				else
					fputc(c, outfile);
				}
			if (tick_changed()) {
				if (outfile != NULL) {
					if (gotchar == 0) {
						gotchar = -1;
						printf(" \x08");
						}
					if (gotchar == 1) {
						gotchar = 0;
						printf("%c %lu bytes\r", ind[(twirly = ++twirly % 4)], charcounter);
						}
					}
				}
			} /* end while(bioskey) */
		bioskey(0);	/* Flush keypress */
		if (outfile != NULL)
			fclose(outfile);
		outfile = NULL;
		putchar('\n');
		return;
	case 'i' :			/* Toggle interrupt / polled modes */
		if (irq < 1) {
			printf("Cannot enable interrupt mode - parallel port has no IRQ\n");
			return;
			}
		intmode = !intmode;
		if (intmode) {
			if (!lptcap_intmode_install(irq, &bd)) {
				intmode = 0;
				printf("Unable to enable interrupt mode on IRQ%u!\n", irq);
				}
			}
		else
			lptcap_intmode_uninstall();
		printf("The LPTCAP system is now operating in %s mode\n", intmode ? "interrupt-driven" : "polled");
		return;
	case 'q' :
	case '\x1B' :
		if (intmode)
			lptcap_intmode_uninstall();
		exit(0);
		return; /* Keep the compiler happy */
	default :
		printf("Unknown command letter - type '?' for help\n");
		break;
		} /* end switch() */
	return;
	}

void main(void) {
	unsigned int lptcap_conds;
	unsigned int num_ports, num_lptcaps;
	unsigned int portnum, portaddr, port, stat;
	unsigned int param;
	int c;

	/* Display LPTCAP module version information */

	lptcap_date.words.loword = lptcap_version(LPTCAP_REQ_DATEL);
	lptcap_date.words.hiword = lptcap_version(LPTCAP_REQ_DATEH);
	lptcap_conds = lptcap_version(LPTCAP_REQ_CONDS);

	printf("\nLPTEST -- Test/demo program for LPTCAP system\n"
	       "\t(c) Copyright 1996-2000 K. Heidenstrom (k@heidenstrom.gen.nz)\n\n");
	printf("\tLPTEST version %u.%u.%u, %s, source file revision %03u\n",
		LPTEST_VERSION, LPTEST_SUBVER, LPTEST_MODVER, LPTEST_DATE,
		LPTEST_REVISION);
	printf("\tLPTCAP version %u.%u.%u, %lu, source file revision %03u\n",
		lptcap_version(LPTCAP_REQ_MAJVER), lptcap_version(LPTCAP_REQ_MINVER),
		lptcap_version(LPTCAP_REQ_MODVER), lptcap_date.ulong,
		lptcap_version(LPTCAP_REQ_FILREV));
	printf("\tCompilation-time parameters: %s code, %s data%s\n\n",
		(lptcap_conds & LPTCAP_COND_FARCODE) ? "far" : "near",
		(lptcap_conds & LPTCAP_COND_FARDATA) ? "far" : "near",
		(lptcap_conds & (LPTCAP_COND_SLOW | LPTCAP_COND_VERYSLOW)) ?
			((lptcap_conds & LPTCAP_COND_VERYSLOW) ? "; VERYSLOW" : "; SLOW") : "");

	/* Display parallel ports present on machine */

	num_ports = num_lptcaps = 0;

	for (portnum = 1; portnum < 5; ++portnum) {
		portaddr = *((unsigned int far *)MK_FP(0x40, 6) + portnum);
		if ((portaddr > 0) && (portaddr < 0x3FE)) {
			++num_ports;
			port = lptcap_port(LPTCAP_FIND_FIRST);
			while ((port != 0) && (port < portnum))
				port = lptcap_port(LPTCAP_FIND_NEXT);
			if (port == portnum) {
				if ((stat = lptcap_test(100)) != 0) {
					printf("\t\tLPT%u   0x%04X   LPTCAP adapter present but faulty\n", portnum, portaddr);
					printf("\t\t\t\tFault: %s\n", status_descriptions[stat]);
					continue;
					}
				++num_lptcaps;
				irq = lptcap_autodetect_irq(0xFFFF);
				if (!irq)
					printf("\t\tLPT%u   0x%04X   LPTCAP adapter present with no IRQ\n", portnum, portaddr);
				if (irq == LPTCAP_IRQ_INVERTED)
					printf("\t\tLPT%u   0x%04X   LPTCAP adapter present; IRQ POLARITY INVERTED\n", portnum, portaddr);
				if (irq == LPTCAP_IRQ_SEVERAL)
					printf("\t\tLPT%u   0x%04X   LPTCAP adapter present on multiple IRQs!\n", portnum, portaddr);
				if ((irq > 1) && (irq < 16))
					printf("\t\tLPT%u   0x%04X   LPTCAP adapter present on IRQ%u\n", portnum, portaddr, irq);
				}
			else
				printf("\t\tLPT%u   0x%04X   LPTCAP adapter not present\n", portnum, portaddr);
			}
		else
			break;	/* Stop at first non-existent port */
		}

	putchar('\n');

	portnum = lptcap_port(LPTCAP_FIND_FIRST);

	if ((num_ports == 0) || (portnum == 0)) {
		printf("Nothing to test\n");
		exit(128);
		}

	if (num_lptcaps == 0) {
		printf("Testing faulty LPTCAP adapter on LPT%u\n", portnum);
		stat = 1;
		while (stat) {
			printf("\n\tSelect function:  [A]djustment signal  [D]iagnostic  [Q]uit? ");
			c = bioskey(0) & 0xFF;
			if (c >= ' ')
				putchar(c);
			putchar('\n');
			switch (tolower(c)) {
			case 'a' :
				printf("Enter number of ticks (or zero for adjust until Ctrl pressed): ");
				gets(input);
				param = (unsigned int) atol(input);
				if (param)
					printf("Generating adjustment signal for %u ticks... ", param);
				else
					printf("Generating adjustment signal, press Ctrl to stop... ");
				lptcap_adjust(param);	/* Do adjustment */
				putchar('\n');
				while (bioskey(1)) bioskey(0);	/* Flush buffer */
				break;
			case 'd' :
				printf("Testing... ");
				stat = lptcap_test(100);
				if (stat)
					printf("\tResult: error %u, %s\n", stat, status_descriptions[stat]);
				else
					printf("\tResult: OK\n");
				if ((stat == LPTCAP_ADAPTER_BSYSTUK) ||
				    (stat == LPTCAP_ADAPTER_STRSTUK))
					printf("\t\tNote - This could be because the Sender is trying to send data.\n"
					       "\t\t       The diagnostic test should be run with the Sender idle.\n");
				break;
			case 'q' :
			case '\x1B':
				exit(1);
				break;		/* Keep compiler happy */
			default :
				break;
				}  /* end switch() */
			} /* end while() */
		printf("\nAdapter is now responding correctly\n\n");
		}

	irq = lptcap_autodetect_irq(0xFFFF);

	if ((intbuf = malloc(INTBUF_SIZE)) == NULL) {
		printf("Fatal error - couldn't allocate the interrupt buffer!\n");
		exit(160);
		}

	bd.buf_size = INTBUF_SIZE;
	bd.buf_base = intbuf;

	if (irq > 0)
		printf("\tTests will use LPTCAP adapter on LPT%u on IRQ%u\n\n", portnum, irq);
	else
		printf("\tTests will use LPTCAP adapter on LPT%u (no IRQ)\n\n", portnum);

	printf("The LPTCAP system is operating in polled mode\n\nType '?' for help\n");

	statuses = 0;

	for (;;)
		do_command();
	}
