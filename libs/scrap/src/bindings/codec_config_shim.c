#include <stdint.h>
#include <stdlib.h>

#include <aom/aomcx.h>
#include <aom/aom_decoder.h>
#include <aom/aom_encoder.h>
#include <vpx/vp8cx.h>
#include <vpx/vpx_decoder.h>
#include <vpx/vpx_encoder.h>

static unsigned int scrap_ceil_log2(unsigned int value) {
    unsigned int result = 0;
    unsigned int current = 1;
    while (current < value) {
        current <<= 1;
        result++;
    }
    return result;
}

static unsigned int scrap_aom_cpu_speed(unsigned int width, unsigned int height) {
    const uint64_t pixels = (uint64_t)width * (uint64_t)height;
    if (pixels <= 320u * 180u) {
        return 8;
    }
    if (pixels <= 640u * 360u) {
        return 9;
    }
    return 10;
}

static aom_superblock_size_t scrap_aom_superblock_size(
    unsigned int width,
    unsigned int height,
    unsigned int threads) {
    const uint64_t pixels = (uint64_t)width * (uint64_t)height;
    if (threads >= 4 && pixels >= 960u * 540u && pixels < 1920u * 1080u) {
        return AOM_SUPERBLOCK_SIZE_64X64;
    }
    return AOM_SUPERBLOCK_SIZE_DYNAMIC;
}

vpx_codec_enc_cfg_t *scrap_vpx_enc_cfg_new(
    vpx_codec_iface_t *iface,
    unsigned int width,
    unsigned int height,
    unsigned int threads,
    unsigned int q_min,
    unsigned int q_max,
    unsigned int bitrate,
    unsigned int keyframe_interval,
    int has_keyframe_interval,
    int use_i444_profile) {
    vpx_codec_enc_cfg_t *cfg = (vpx_codec_enc_cfg_t *)calloc(1, sizeof(*cfg));
    if (cfg == NULL) {
        return NULL;
    }
    if (vpx_codec_enc_config_default(iface, cfg, 0) != VPX_CODEC_OK) {
        free(cfg);
        return NULL;
    }

    cfg->g_w = width;
    cfg->g_h = height;
    cfg->g_timebase.num = 1;
    cfg->g_timebase.den = 1000;
    cfg->rc_undershoot_pct = 95;
    cfg->rc_dropframe_thresh = 25;
    cfg->g_threads = threads;
    cfg->g_error_resilient = VPX_ERROR_RESILIENT_DEFAULT;
    cfg->rc_end_usage = VPX_CBR;
    if (has_keyframe_interval) {
        cfg->kf_min_dist = 0;
        cfg->kf_max_dist = keyframe_interval;
    } else {
        cfg->kf_mode = VPX_KF_DISABLED;
    }
    cfg->rc_min_quantizer = q_min;
    cfg->rc_max_quantizer = q_max;
    cfg->rc_target_bitrate = bitrate;
    cfg->g_profile = use_i444_profile ? 1 : 0;
    return cfg;
}

void scrap_vpx_enc_cfg_free(vpx_codec_enc_cfg_t *cfg) {
    free(cfg);
}

vpx_codec_err_t scrap_vpx_enc_cfg_update_quality(
    vpx_codec_enc_cfg_t *cfg,
    unsigned int q_min,
    unsigned int q_max,
    unsigned int bitrate) {
    if (cfg == NULL) {
        return VPX_CODEC_INVALID_PARAM;
    }
    cfg->rc_min_quantizer = q_min;
    cfg->rc_max_quantizer = q_max;
    cfg->rc_target_bitrate = bitrate;
    return VPX_CODEC_OK;
}

unsigned int scrap_vpx_enc_cfg_bitrate(const vpx_codec_enc_cfg_t *cfg) {
    if (cfg == NULL) {
        return 0;
    }
    return cfg->rc_target_bitrate;
}

vpx_codec_dec_cfg_t *scrap_vpx_dec_cfg_new(unsigned int threads) {
    vpx_codec_dec_cfg_t *cfg = (vpx_codec_dec_cfg_t *)calloc(1, sizeof(*cfg));
    if (cfg == NULL) {
        return NULL;
    }
    cfg->threads = threads;
    cfg->w = 0;
    cfg->h = 0;
    return cfg;
}

void scrap_vpx_dec_cfg_free(vpx_codec_dec_cfg_t *cfg) {
    free(cfg);
}

aom_codec_enc_cfg_t *scrap_aom_enc_cfg_new(
    aom_codec_iface_t *iface,
    unsigned int width,
    unsigned int height,
    unsigned int threads,
    unsigned int q_min,
    unsigned int q_max,
    unsigned int bitrate,
    unsigned int keyframe_interval,
    int has_keyframe_interval,
    int use_i444_profile) {
    aom_codec_enc_cfg_t *cfg = (aom_codec_enc_cfg_t *)calloc(1, sizeof(*cfg));
    if (cfg == NULL) {
        return NULL;
    }
    if (aom_codec_enc_config_default(iface, cfg, AOM_USAGE_REALTIME) != AOM_CODEC_OK) {
        free(cfg);
        return NULL;
    }

    cfg->g_w = width;
    cfg->g_h = height;
    cfg->g_threads = threads;
    cfg->g_timebase.num = 1;
    cfg->g_timebase.den = 1000;
    cfg->g_input_bit_depth = 8;
    if (has_keyframe_interval) {
        cfg->kf_min_dist = 0;
        cfg->kf_max_dist = keyframe_interval;
    } else {
        cfg->kf_mode = AOM_KF_DISABLED;
    }
    cfg->rc_min_quantizer = q_min;
    cfg->rc_max_quantizer = q_max;
    cfg->rc_target_bitrate = bitrate;
    cfg->rc_undershoot_pct = 50;
    cfg->rc_overshoot_pct = 50;
    cfg->rc_buf_initial_sz = 600;
    cfg->rc_buf_optimal_sz = 600;
    cfg->rc_buf_sz = 1000;
    cfg->g_usage = AOM_USAGE_REALTIME;
    cfg->g_error_resilient = 0;
    cfg->rc_end_usage = AOM_CBR;
    cfg->g_pass = AOM_RC_ONE_PASS;
    cfg->g_lag_in_frames = 0;
    cfg->g_profile = use_i444_profile ? 1 : 0;
    return cfg;
}

void scrap_aom_enc_cfg_free(aom_codec_enc_cfg_t *cfg) {
    free(cfg);
}

aom_codec_err_t scrap_aom_enc_cfg_update_quality(
    aom_codec_enc_cfg_t *cfg,
    unsigned int q_min,
    unsigned int q_max,
    unsigned int bitrate) {
    if (cfg == NULL) {
        return AOM_CODEC_INVALID_PARAM;
    }
    cfg->rc_min_quantizer = q_min;
    cfg->rc_max_quantizer = q_max;
    cfg->rc_target_bitrate = bitrate;
    return AOM_CODEC_OK;
}

unsigned int scrap_aom_enc_cfg_bitrate(const aom_codec_enc_cfg_t *cfg) {
    if (cfg == NULL) {
        return 0;
    }
    return cfg->rc_target_bitrate;
}

aom_codec_err_t scrap_aom_apply_realtime_controls(
    aom_codec_ctx_t *ctx,
    const aom_codec_enc_cfg_t *cfg) {
    if (ctx == NULL || cfg == NULL) {
        return AOM_CODEC_INVALID_PARAM;
    }

#define SCRAP_AOM_CTL(id, value) (void)aom_codec_control(ctx, id, value)
    SCRAP_AOM_CTL(AOME_SET_CPUUSED, (int)scrap_aom_cpu_speed(cfg->g_w, cfg->g_h));
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_CDEF, 1u);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_TPL_MODEL, 0u);
    SCRAP_AOM_CTL(AV1E_SET_DELTAQ_MODE, 0u);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_ORDER_HINT, 0);
    SCRAP_AOM_CTL(AV1E_SET_AQ_MODE, 3u);
    SCRAP_AOM_CTL(AOME_SET_MAX_INTRA_BITRATE_PCT, 300u);
    SCRAP_AOM_CTL(AV1E_SET_COEFF_COST_UPD_FREQ, 3u);
    SCRAP_AOM_CTL(AV1E_SET_MODE_COST_UPD_FREQ, 3u);
    SCRAP_AOM_CTL(AV1E_SET_MV_COST_UPD_FREQ, 3u);
    SCRAP_AOM_CTL(AV1E_SET_TUNE_CONTENT, AOM_CONTENT_SCREEN);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_PALETTE, 1);
    if (cfg->g_threads == 4 && cfg->g_w == 640 && (cfg->g_h == 360 || cfg->g_h == 480)) {
        SCRAP_AOM_CTL(AV1E_SET_TILE_ROWS, scrap_ceil_log2(cfg->g_threads));
    } else {
        SCRAP_AOM_CTL(AV1E_SET_TILE_COLUMNS, scrap_ceil_log2(cfg->g_threads));
    }
    SCRAP_AOM_CTL(AV1E_SET_ROW_MT, 1u);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_OBMC, 0u);
    SCRAP_AOM_CTL(AV1E_SET_NOISE_SENSITIVITY, 0u);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_WARPED_MOTION, 0);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_GLOBAL_MOTION, 0);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_REF_FRAME_MVS, 0);
    SCRAP_AOM_CTL(
        AV1E_SET_SUPERBLOCK_SIZE,
        (unsigned int)scrap_aom_superblock_size(cfg->g_w, cfg->g_h, cfg->g_threads));
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_CFL_INTRA, 0);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_SMOOTH_INTRA, 0);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_ANGLE_DELTA, 0);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_FILTER_INTRA, 0);
    SCRAP_AOM_CTL(AV1E_SET_INTRA_DEFAULT_TX_ONLY, 1);
    SCRAP_AOM_CTL(AV1E_SET_DISABLE_TRELLIS_QUANT, 1u);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_DIST_WTD_COMP, 0);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_DIFF_WTD_COMP, 0);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_DUAL_FILTER, 0);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_INTERINTRA_COMP, 0);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_INTERINTRA_WEDGE, 0);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_INTRA_EDGE_FILTER, 0);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_INTRABC, 0);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_MASKED_COMP, 0);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_PAETH_INTRA, 0);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_QM, 0u);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_RECT_PARTITIONS, 0);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_RESTORATION, 0u);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_SMOOTH_INTERINTRA, 0);
    SCRAP_AOM_CTL(AV1E_SET_ENABLE_TX64, 0);
    SCRAP_AOM_CTL(AV1E_SET_MAX_REFERENCE_FRAMES, 3);
#undef SCRAP_AOM_CTL

    return AOM_CODEC_OK;
}

aom_codec_dec_cfg_t *scrap_aom_dec_cfg_new(unsigned int threads) {
    aom_codec_dec_cfg_t *cfg = (aom_codec_dec_cfg_t *)calloc(1, sizeof(*cfg));
    if (cfg == NULL) {
        return NULL;
    }
    cfg->threads = threads;
    cfg->w = 0;
    cfg->h = 0;
    cfg->allow_lowbitdepth = 1;
    return cfg;
}

void scrap_aom_dec_cfg_free(aom_codec_dec_cfg_t *cfg) {
    free(cfg);
}
