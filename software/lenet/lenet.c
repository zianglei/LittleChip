#include "types.h"
#include "ascii.h"
#include "uart.h"
#include "memory_map.h"
#include "cnn.h"

#define BUF_LEN 128

#define NUM_TEST_IMAGES 128
#define NUM_LABELS ((NUM_TEST_IMAGES < 4) ? 4 : NUM_TEST_IMAGES)

static int8_t wt_conv1[WT_CONV1_SIZE];
static int8_t wt_conv2[WT_CONV2_SIZE];
static int8_t wt_fc   [WT_FC_SIZE];

static int8_t img[IMG_SIZE];
static char test_labels[NUM_TEST_IMAGES];

typedef void (*entry_t)(void);

// Find the maximum value of FC_DEPTH elements
void findmax(int32_t *input, char *labels, int img_index) {
  int f;
  int32_t max = input[0];
  char max_pos = 0;
  for (f = 1; f < FC_DEPTH; ++f) {
    if (max < input[f]) {
      max = input[f];
      max_pos = f;
    }
    labels[img_index] = max_pos;
  }
}

void dma_read_ddr(uint32_t src_addr, uint32_t dst_addr, int dma_len) {
  DMA_DIR      = 0; // DDR -> Riscv DMem
  DMA_SRC_ADDR = src_addr;
  DMA_DST_ADDR = dst_addr;
  DMA_LEN      = dma_len;
  DMA_START    = 1;
  while (!DMA_DONE);
}

void dma_write_ddr(uint32_t src_addr, uint32_t dst_addr, int dma_len) {
  DMA_DIR      = 1; // Riscv DMem -> DDR
  DMA_SRC_ADDR = src_addr;
  DMA_DST_ADDR = dst_addr;
  DMA_LEN      = dma_len;
  DMA_START    = 1;
  while (!DMA_DONE);
}

void conv3D_hw(uint32_t ifm_ddr_addr, uint32_t wt_ddr_addr, uint32_t ofm_ddr_addr,
               uint32_t ifm_dim, uint32_t ifm_depth, uint32_t wt_dim,
               uint32_t ofm_dim, uint32_t ofm_depth) {

  XCEL_IFM_DDR_ADDR = ifm_ddr_addr;
  XCEL_WT_DDR_ADDR  = wt_ddr_addr;
  XCEL_OFM_DDR_ADDR = ofm_ddr_addr;
  XCEL_OFM_DIM      = ofm_dim;
  XCEL_OFM_DEPTH    = ofm_depth;
  XCEL_WT_DIM       = wt_dim;
  XCEL_IFM_DIM      = ifm_dim;
  XCEL_IFM_DEPTH    = ifm_depth;
  XCEL_START         = 1;

  while (!XCEL_DONE);
}

void lenet(int8_t *img, int8_t *wt_conv1, int8_t *wt_conv2, int8_t *wt_fc,
           int32_t *conv1_ofm, int32_t *conv2_ofm,
           int8_t *pool1_ofm, int8_t *pool2_ofm,
           int32_t *fc_ofm,
           char *labels, int img_index) {

  conv3D_sw_1(img, wt_conv1, conv1_ofm);
  clamp(conv1_ofm, CONV1_OFM_SIZE);
  pooling_sw_1(conv1_ofm, pool1_ofm);
  conv3D_sw_2(pool1_ofm, wt_conv2, conv2_ofm);
  clamp(conv2_ofm, CONV2_OFM_SIZE);
  pooling_sw_2(conv2_ofm, pool2_ofm);
  fc_sw(pool2_ofm, wt_fc, fc_ofm);
  findmax(fc_ofm, labels, img_index);
}

int32_t checksum_i32(int32_t *input, int len) {
  int32_t sum = 0;
  int i;
  for (i = 0; i < len; i++) {
    int32_t val = (input[i]);
    sum += val;
  }

  return sum;
}

int32_t checksum_i8(int8_t *input, int len) {
  int32_t sum = 0;
  int i;
  for (i = 0; i < len; i++) {
    int32_t val = cast_si32(input[i]);
    sum += val;
  }

  return sum;
}

int main(int argc, char**argv) {
  int8_t buffer[BUF_LEN];
  int i;

  // Load wt_conv1
  dma_read_ddr(WT_CONV1_DDR_ADDR,
               (uint32_t)wt_conv1 >> 2,
               WT_CONV1_SIZE >> 2);
  // Load wt_conv2
  dma_read_ddr(WT_CONV2_DDR_ADDR,
               (uint32_t)wt_conv2 >> 2,
               WT_CONV2_SIZE >> 2);
  // Load wt_fc
  dma_read_ddr(WT_FC_DDR_ADDR,
               (uint32_t)wt_fc >> 2,
               WT_FC_SIZE >> 2);

  // Load groundtruth labels
  dma_read_ddr(LABELS_DDR_ADDR,
               (uint32_t)test_labels >> 2,
               NUM_LABELS >> 2);

  int32_t conv1_ofm[CONV1_OFM_SIZE];
  int32_t conv2_ofm[CONV2_OFM_SIZE];

  int8_t pool1_ofm[POOL1_OFM_SIZE];
  int8_t pool2_ofm[POOL2_OFM_SIZE];

  int32_t fc_ofm[FC_DEPTH];

  char pred_labels[NUM_LABELS];
  uint32_t num_corrects = 0;
  uint32_t time = 0;

  for (i = 0; i < NUM_TEST_IMAGES; i++) {
    uwrite_int8s("\r\n>>> Processing image: ");
    uwrite_int8s(uint32_to_ascii_hex(i, buffer, BUF_LEN));

    // Benchmark
    COUNTER_RST = 0;

    // Read image from DDR
    dma_read_ddr(IMAGES_DDR_ADDR + i * IMG_SIZE,
                 (uint32_t)img >> 2,
                 (IMG_SIZE) / sizeof(int8_t));
    lenet(img, wt_conv1, wt_conv2, wt_fc,
          conv1_ofm, conv2_ofm,
          pool1_ofm, pool2_ofm,
          fc_ofm,
          pred_labels, i);

    time += CYCLE_COUNTER;

    uwrite_int8s("\r\nPrediction: ");
    uwrite_int8s(uint32_to_ascii_hex(pred_labels[i], buffer, BUF_LEN));
    uwrite_int8s("\r\nGroundtruth: ");
    uwrite_int8s(uint32_to_ascii_hex(test_labels[i], buffer, BUF_LEN));

    if (pred_labels[i] == test_labels[i]) {
      num_corrects += 1;
    } else {
      uwrite_int8s("\r\nMispredicted!");
    }
  }

  uwrite_int8s("\r\nCycle Count: ");
  uwrite_int8s(uint32_to_ascii_hex(time, buffer, BUF_LEN));

  uwrite_int8s("\r\nNumber of test images: ");
  uwrite_int8s(uint32_to_ascii_hex(NUM_TEST_IMAGES, buffer, BUF_LEN));
  uwrite_int8s("\r\nNumber of correct predictions: ");
  uwrite_int8s(uint32_to_ascii_hex(num_corrects, buffer, BUF_LEN));

  // go back to the bios - using this function causes a jr to the addr,
  // the compiler "jals" otherwise and then cannot set PC[31:28]
  uint32_t bios = ascii_hex_to_uint32("40000000");
  entry_t start = (entry_t) (bios);
  start();
  return 0;
}
