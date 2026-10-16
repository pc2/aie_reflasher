/*
 * aie_reflasher firmware: bare-metal (standalone BSP) on Cortex-A72 #0 of the VCK5000.
 *
 * It does one thing: when the host drops a partial PDI into card DDR and rings a
 * mailbox, it asks the PLM (via the XilLoader "Load Subsystem PDI" IPI command)
 * to load that PDI. The PLM then executes the AIE CDOs itself, including the NPI
 * writes at 0xF70A0000 that nothing outside the PMC is allowed to do.
 *
 * This is the same mechanism XRT uses on the VCK5000 shell: VMR (on the R5) calls
 * xilfpga -> XMailbox -> IPI {0x030701, 0xF (DDR), addr_hi, addr_lo} -> PLM.
 * See Xilinx/VMR vmr/src/rmgmt/rmgmt_xfer.c and
 * embeddedsw lib/sw_services/xilfpga/src/interface/versal/xilfpga_versal.c.
 */
#include <stdint.h>
#include <string.h>

#include "xparameters.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xipipsu.h"
#include "sleep.h"

#include "reflash_proto.h"

/* ---- IPI command to the PLM -------------------------------------------- */
/* Header = (payload_len << 16) | (module_id << 8) | cmd_id
 * XilLoader module id = 7, cmd 1 = LOAD_SUBSYSTEM_PDI, payload = {src, addr_hi, addr_lo} */
#define PLM_CMD_LOAD_PDI        0x030701U
#define PLM_PDI_SRC_DDR         0xFU
#define PLM_IPI_TIMEOUT         0xFFFFFFFFU   /* XIpiPsu_PollForAck iterations */

/* IPI mask of the PMC. The BSP normally provides this; 0x2 is the Versal PMC bit.
 * Verify against xparameters.h of your BSP. */
#ifdef XPAR_XIPIPS_TARGET_PSV_PMC_0_CH0_MASK
#define PMC_IPI_MASK            XPAR_XIPIPS_TARGET_PSV_PMC_0_CH0_MASK
#else
#warning "XPAR_XIPIPS_TARGET_PSV_PMC_0_CH0_MASK not found, falling back to 0x2"
#define PMC_IPI_MASK            0x2U
#endif

/* ---- Mailbox in DDR ----------------------------------------------------- */
#define REGION_PS_BASE  (REFLASH_DDR_PS_BASE + REFLASH_REGION_DEV_OFFSET)

static volatile struct reflash_req  *req  = (volatile struct reflash_req  *)(uintptr_t)(REGION_PS_BASE + REFLASH_REQ_OFF);
static volatile struct reflash_resp *resp = (volatile struct reflash_resp *)(uintptr_t)(REGION_PS_BASE + REFLASH_RESP_OFF);
static volatile char                *logbuf = (volatile char *)(uintptr_t)(REGION_PS_BASE + REFLASH_LOG_OFF);

static XIpiPsu ipi;
static struct reflash_resp shadow;   /* local copy, written out with a cache flush */

static void resp_publish(void)
{
    memcpy((void *)resp, &shadow, sizeof(shadow));
    Xil_DCacheFlushRange((INTPTR)resp, sizeof(*resp));
}

/* Tiny log ring in DDR so the host can read it; useful when no UART cable is attached. */
static void log_str(const char *s)
{
    while (*s) {
        logbuf[shadow.log_wr % REFLASH_LOG_SIZE] = *s++;
        shadow.log_wr++;
    }
    Xil_DCacheFlushRange((INTPTR)logbuf, REFLASH_LOG_SIZE);
    xil_printf("%s", s);
}

static void log_hex(const char *prefix, uint64_t v)
{
    static const char hexd[] = "0123456789abcdef";
    char buf[32];
    int i = 0;
    while (prefix[i] && i < 12) { buf[i] = prefix[i]; i++; }
    buf[i++] = '0'; buf[i++] = 'x';
    for (int s = 60; s >= 0; s -= 4)
        buf[i++] = hexd[(v >> s) & 0xF];
    buf[i++] = '\n';
    buf[i] = 0;
    log_str(buf);
}

static int ipi_init(void)
{
#ifdef SDT
    XIpiPsu_Config *cfg = XIpiPsu_LookupConfig(XPAR_XIPIPSU_0_BASEADDR);
#else
    XIpiPsu_Config *cfg = XIpiPsu_LookupConfig(XPAR_XIPIPSU_0_DEVICE_ID);
#endif
    if (cfg == NULL)
        return -1;
    if (XIpiPsu_CfgInitialize(&ipi, cfg, cfg->BaseAddress) != XST_SUCCESS)
        return -2;
    return 0;
}

/* Send LOAD_SUBSYSTEM_PDI to the PLM and wait for the answer. */
static uint32_t plm_load_pdi(uint64_t pdi_ps_addr, uint32_t *plmi_status, uint32_t *loader_status)
{
    uint32_t payload[4] = {
        PLM_CMD_LOAD_PDI,
        PLM_PDI_SRC_DDR,
        (uint32_t)(pdi_ps_addr >> 32),
        (uint32_t)(pdi_ps_addr & 0xFFFFFFFFU),
    };
    uint32_t response[2] = { 0xDEADBEEFU, 0xDEADBEEFU };

    if (XIpiPsu_WriteMessage(&ipi, PMC_IPI_MASK, payload, 4, XIPIPSU_BUF_TYPE_MSG) != XST_SUCCESS)
        return REFLASH_ERR_IPI_WRITE;
    if (XIpiPsu_TriggerIpi(&ipi, PMC_IPI_MASK) != XST_SUCCESS)
        return REFLASH_ERR_IPI_TRIGGER;
    if (XIpiPsu_PollForAck(&ipi, PMC_IPI_MASK, PLM_IPI_TIMEOUT) != XST_SUCCESS)
        return REFLASH_ERR_IPI_TIMEOUT;
    if (XIpiPsu_ReadMessage(&ipi, PMC_IPI_MASK, response, 2, XIPIPSU_BUF_TYPE_RESP) != XST_SUCCESS)
        return REFLASH_ERR_IPI_READ;

    *plmi_status = response[0];
    *loader_status = response[1];
    return (response[0] == 0U) ? REFLASH_ERR_NONE : REFLASH_ERR_PLM;
}

static void handle_request(const struct reflash_req *r)
{
    shadow.seq = r->seq;
    shadow.state = REFLASH_STATE_BUSY;
    shadow.fw_error = REFLASH_ERR_NONE;
    shadow.plmi_status = 0;
    shadow.loader_status = 0;
    resp_publish();

    switch (r->cmd) {
    case REFLASH_CMD_PING:
        log_str("ping\n");
        shadow.state = REFLASH_STATE_OK;
        break;

    case REFLASH_CMD_LOAD_PDI: {
        uint64_t addr = REFLASH_DDR_PS_BASE + r->pdi_dev_offset;
        if (r->pdi_size == 0 || r->pdi_size > REFLASH_PDI_MAX || (r->pdi_size & 3U)) {
            shadow.fw_error = REFLASH_ERR_BAD_SIZE;
            shadow.state = REFLASH_STATE_ERROR;
            break;
        }
        if (addr & 0x3FU) {
            shadow.fw_error = REFLASH_ERR_BAD_ALIGN;
            shadow.state = REFLASH_STATE_ERROR;
            break;
        }
        log_hex("load pdi @", addr);
        /* The PDI was written to DDR by the host DMA; the A72 never touched it, so
         * there is nothing to flush on our side. The PLM reads it with the PMC DMA. */
        shadow.fw_error = plm_load_pdi(addr, &shadow.plmi_status, &shadow.loader_status);
        log_hex("plmi   =", shadow.plmi_status);
        log_hex("loader =", shadow.loader_status);
        if (shadow.fw_error == REFLASH_ERR_NONE) {
            shadow.loads_done++;
            shadow.state = REFLASH_STATE_OK;
        } else {
            shadow.state = REFLASH_STATE_ERROR;
        }
        break;
    }

    default:
        shadow.fw_error = REFLASH_ERR_BAD_CMD;
        shadow.state = REFLASH_STATE_ERROR;
        break;
    }
    resp_publish();
}

int main(void)
{
    struct reflash_req local;
    uint32_t last_seq;

    memset(&shadow, 0, sizeof(shadow));
    shadow.fw_version = REFLASH_FW_VERSION;
    shadow.state = REFLASH_STATE_IDLE;

    if (ipi_init() != 0) {
        /* No IPI: still publish the mailbox so the host can see we are alive but broken. */
        shadow.fw_error = REFLASH_ERR_IPI_WRITE;
        shadow.state = REFLASH_STATE_ERROR;
    }
    shadow.magic = REFLASH_MAGIC;
    resp_publish();
    log_str("aie_reflasher fw up\n");

    /* Start from whatever seq the host left in the request block. */
    Xil_DCacheInvalidateRange((INTPTR)req, sizeof(*req));
    last_seq = (req->magic == REFLASH_MAGIC) ? req->seq : 0;

    for (;;) {
        Xil_DCacheInvalidateRange((INTPTR)req, sizeof(*req));
        memcpy(&local, (const void *)req, sizeof(local));
        if (local.magic == REFLASH_MAGIC && local.seq != last_seq) {
            last_seq = local.seq;
            handle_request(&local);
        } else {
            usleep(500);
        }
    }
    return 0;
}
