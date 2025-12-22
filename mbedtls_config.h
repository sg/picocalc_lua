/*
 * Minimal mbedTLS configuration for PicoCalc HTTPS client
 * Based on pico-sdk kitchen_sink example
 */
#ifndef MBEDTLS_CONFIG_H
#define MBEDTLS_CONFIG_H

/* Workaround for some mbedtls source files using INT_MAX without limits.h */
#include <limits.h>

/* System support */
#define MBEDTLS_HAVE_TIME
#define MBEDTLS_NO_PLATFORM_ENTROPY
#define MBEDTLS_ENTROPY_HARDWARE_ALT

/* Platform */
#define MBEDTLS_PLATFORM_C
#define MBEDTLS_PLATFORM_MS_TIME_ALT

/* Memory optimization */
#define MBEDTLS_SSL_OUT_CONTENT_LEN     2048
#define MBEDTLS_SSL_IN_CONTENT_LEN      8192
#define MBEDTLS_AES_FEWER_TABLES
#define MBEDTLS_SHA256_SMALLER

/* Allow private access for lwIP altcp_tls */
#define MBEDTLS_ALLOW_PRIVATE_ACCESS

/* Core cryptographic modules */
#define MBEDTLS_AES_C
#define MBEDTLS_ASN1_PARSE_C
#define MBEDTLS_ASN1_WRITE_C
#define MBEDTLS_BIGNUM_C
#define MBEDTLS_CIPHER_C
#define MBEDTLS_CTR_DRBG_C
#define MBEDTLS_ENTROPY_C
#define MBEDTLS_ERROR_C
#define MBEDTLS_MD_C
#define MBEDTLS_MD5_C
#define MBEDTLS_OID_C
#define MBEDTLS_PK_C
#define MBEDTLS_PK_PARSE_C
#define MBEDTLS_PKCS5_C
#define MBEDTLS_RSA_C
#define MBEDTLS_SHA1_C
#define MBEDTLS_SHA224_C
#define MBEDTLS_SHA256_C
#define MBEDTLS_SHA512_C

/* Cipher modes */
#define MBEDTLS_CIPHER_MODE_CBC
#define MBEDTLS_GCM_C

/* RSA/PKCS */
#define MBEDTLS_PKCS1_V15

/* Elliptic curves - minimal set for modern TLS */
#define MBEDTLS_ECP_C
#define MBEDTLS_ECDH_C
#define MBEDTLS_ECDSA_C
#define MBEDTLS_ECP_DP_SECP256R1_ENABLED
#define MBEDTLS_ECP_DP_SECP384R1_ENABLED
#define MBEDTLS_ECP_DP_CURVE25519_ENABLED

/* Key exchange - required for TLS */
#define MBEDTLS_KEY_EXCHANGE_RSA_ENABLED
#define MBEDTLS_KEY_EXCHANGE_ECDHE_ECDSA_ENABLED
#define MBEDTLS_KEY_EXCHANGE_ECDHE_RSA_ENABLED

/* SSL/TLS - client only */
#define MBEDTLS_SSL_TLS_C
#define MBEDTLS_SSL_CLI_C
#define MBEDTLS_SSL_PROTO_TLS1_2

/* X.509 certificate parsing (needed even without verification) */
#define MBEDTLS_X509_USE_C
#define MBEDTLS_X509_CRT_PARSE_C

/* Server Name Indication - required by many HTTPS servers */
#define MBEDTLS_SSL_SERVER_NAME_INDICATION

/* Disable features we don't need to save space */
/* #define MBEDTLS_SSL_SRV_C */           /* No TLS server */
/* #define MBEDTLS_SSL_PROTO_TLS1_3 */    /* TLS 1.2 is sufficient */
/* #define MBEDTLS_DEBUG_C */             /* Disable debug */

#endif /* MBEDTLS_CONFIG_H */
