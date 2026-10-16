/*
 * Shared host <-> firmware protocol for the PMC-based AI Engine reflasher.
 *
 * Everything lives in card DDR. Tapasco "device addresses" are offsets into
 * DDR; the PS (A72 / PMC) sees the same bytes at REFLASH_DDR_PS_BASE + offset
 * (Tapasco maps the memory controllers to the DDR_LOW3 NoC region).
 *
 * Layout of the reserved region (REFLASH_REGION_DEV_OFFSET, REFLASH_REGION_SIZE):
 *
 *   +0x0000  struct reflash_req   (64 B, written by host only)
 *   +0x0040  struct reflash_resp  (64 B, written by firmware only)
 *   +0x1000  log ring             (REFLASH_LOG_SIZE, written by firmware only)
 *   +0x10000 partial PDI image    (up to REFLASH_PDI_MAX, written by host only)
 *
 * Host and firmware never write the same cache line.
 */
#ifndef REFLASH_PROTO_H
#define REFLASH_PROTO_H

#include <stdint.h>

#define REFLASH_DDR_PS_BASE        0x10000000000ULL /* DDR_LOW3 as seen by PS/PMC */

#define REFLASH_REGION_DEV_OFFSET  0x0ULL           /* Tapasco device address of the region */
#define REFLASH_REQ_OFF            0x0000U
#define REFLASH_RESP_OFF           0x0040U
#define REFLASH_LOG_OFF            0x1000U
#define REFLASH_LOG_SIZE           0x1000U
#define REFLASH_PDI_OFF            0x10000U
#define REFLASH_PDI_MAX            0x1000000U       /* 16 MiB */
#define REFLASH_REGION_SIZE        (REFLASH_PDI_OFF + REFLASH_PDI_MAX)

#define REFLASH_MAGIC              0x52454941U      /* "AIER" */
#define REFLASH_FW_VERSION         1U

/* req.cmd */
#define REFLASH_CMD_NONE           0U
#define REFLASH_CMD_LOAD_PDI       1U   /* ask the PLM to load the partial PDI at pdi_dev_offset */
#define REFLASH_CMD_PING           2U   /* no-op, just bumps resp.seq */

/* resp.state */
#define REFLASH_STATE_IDLE         0U
#define REFLASH_STATE_BUSY         1U
#define REFLASH_STATE_OK           2U
#define REFLASH_STATE_ERROR        3U

/* resp.fw_error (firmware-side errors, distinct from PLM status codes) */
#define REFLASH_ERR_NONE           0U
#define REFLASH_ERR_BAD_CMD        1U
#define REFLASH_ERR_BAD_SIZE       2U
#define REFLASH_ERR_BAD_ALIGN      3U
#define REFLASH_ERR_IPI_WRITE      4U
#define REFLASH_ERR_IPI_TRIGGER    5U
#define REFLASH_ERR_IPI_TIMEOUT    6U
#define REFLASH_ERR_IPI_READ       7U
#define REFLASH_ERR_PLM            8U   /* PLM returned non-zero; see plmi_status / loader_status */

struct reflash_req {
    uint32_t magic;          /* REFLASH_MAGIC */
    uint32_t seq;            /* incremented by host for every new request */
    uint32_t cmd;            /* REFLASH_CMD_* */
    uint32_t pdi_size;       /* bytes, multiple of 4 */
    uint64_t pdi_dev_offset; /* Tapasco device address of the PDI (normally region + REFLASH_PDI_OFF) */
    uint32_t reserved[10];
};

struct reflash_resp {
    uint32_t magic;          /* REFLASH_MAGIC once firmware is up */
    uint32_t seq;            /* seq of the request this response belongs to */
    uint32_t state;          /* REFLASH_STATE_* */
    uint32_t fw_error;       /* REFLASH_ERR_* */
    uint32_t plmi_status;    /* IPI response word 0 (XilPlmi status) */
    uint32_t loader_status;  /* IPI response word 1 (XilLoader status) */
    uint32_t fw_version;
    uint32_t loads_done;
    uint32_t log_wr;         /* write index into the log ring (bytes) */
    uint32_t reserved[7];
};

#endif /* REFLASH_PROTO_H */
