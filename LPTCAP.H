/* LPTCAP.H  --  Header file for LPTCAP module - k@heidenstrom.gen.nz

	(c) Copyright 1996-2000 K. Heidenstrom, may be freely used
		provided that copyright information is retained

KH.19971018.001  First version-tracked version
KH.19971220.002  Release version - release 1
KH.20000402.003  Email address kheidens@clear.net.nz -> k@heidenstrom.gen.nz
*/

/* Constants */

#define LPTCAP_REQ_MAJVER 0	/* Values for request parameter */
#define LPTCAP_REQ_MINVER 1
#define LPTCAP_REQ_MODVER 2
#define LPTCAP_REQ_FILREV 3
#define LPTCAP_REQ_DATEL  4
#define LPTCAP_REQ_DATEH  5
#define LPTCAP_REQ_CONDS  6

#define LPTCAP_COND_VERYSLOW 8	/* Bitmasks for LPTCAP_REQ_CONDS return value */
#define LPTCAP_COND_SLOW     4
#define LPTCAP_COND_FARDATA  2
#define LPTCAP_COND_FARCODE  1

#define LPTCAP_FIND_SAME  0	/* Values for findmode */
#define LPTCAP_FIND_FIRST 1
#define LPTCAP_FIND_NEXT  2

#define LPTCAP_ADAPTER_PRESENT 0	/* Return values from lptcap_test() */
#define LPTCAP_ADAPTER_NO_PORT 1
#define LPTCAP_ADAPTER_MISSING 2
#define LPTCAP_ADAPTER_INTMODE 3
#define LPTCAP_ADAPTER_NO_DRDY 4
#define LPTCAP_ADAPTER_ACKSTUK 5
#define LPTCAP_ADAPTER_NO_DACK 6
#define LPTCAP_ADAPTER_ACKLONG 7
#define LPTCAP_ADAPTER_BSYSTUK 8
#define LPTCAP_ADAPTER_STRSTUK 9
#define LPTCAP_ADAPTER_SDISERR 10
#define LPTCAP_ADAPTER_DATAERR 11

#define LPTCAP_CONT_SELECT     8	/* Values from lpt_get_cont() */
#define LPTCAP_CONT_INITIALIZE 4
#define LPTCAP_CONT_AUTOFEED   2

#define LPTCAP_STAT_PAPEROUT	0x20	/* Values for lptcap_set_stat() */
#define LPTCAP_STAT_NOTSELECTED 0x10
#define LPTCAP_STAT_ERROR	0x08

#define LPTCAP_IRQ_NONE		0	/* Values from lptcap_detect_irq() */
#define LPTCAP_IRQ_INVERTED	(-1)	/* IRQ found but was inverted */
#define LPTCAP_IRQ_SEVERAL	(-2)	/* More than one IRQ found */

#define LPTCAP_NOCHAR		(-1)	/* No char available indication */
			/* from lptcap_next_char() and lptcap_wait_char() */

/* Typedefs */

typedef struct {
	volatile unsigned int tail_index;
	unsigned int head_index;
	unsigned int buf_size;
	unsigned char * buf_base;
	} lptcap_bufdescriptor;

/* Function prototypes */

unsigned int	lptcap_version		(int request);
int		lptcap_port		(int findmode);
int		lptcap_test		(unsigned int ntests);
unsigned int	lptcap_test_fail_data	(void);
void		lptcap_adjust		(unsigned int ticks);
int		lptcap_autodetect_irq	(unsigned int irq_mask);
unsigned int	lptcap_get_cont		(void);
void		lptcap_set_stat		(unsigned int stat_word);
void		lptcap_send_ack		(void);
int		lptcap_poll_new		(void);
int		lptcap_next_char	(void);
int		lptcap_wait_char	(unsigned int timeout_ticks);
int		lptcap_intmode_install	(unsigned int irqnum,
					 lptcap_bufdescriptor * bdp);
void		lptcap_intmode_uninstall(void);

/* End of file */
