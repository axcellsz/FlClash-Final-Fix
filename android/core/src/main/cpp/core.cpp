#include <jni.h>

#ifdef LIBCLASH

#include "jni_helper.h"
#include "libclash.h"
#include "bride.h"

extern "C"
JNIEXPORT void JNICALL
Java_com_follow_clash_core_Core_startTun(JNIEnv *env, jobject thiz, jint fd, jobject cb,
                                         jstring stack, jstring address, jstring dns) {
    const auto interface = new_global(cb);
    startTUN(interface, fd, get_string(stack), get_string(address), get_string(dns));
}

extern "C"
JNIEXPORT void JNICALL
Java_com_follow_clash_core_Core_stopTun(JNIEnv *env, jobject thiz) {
    stopTun();
}

extern "C"
JNIEXPORT void JNICALL
Java_com_follow_clash_core_Core_forceGC(JNIEnv *env, jobject thiz) {
    forceGC();
}

extern "C"
JNIEXPORT void JNICALL
Java_com_follow_clash_core_Core_updateDNS(JNIEnv *env, jobject thiz, jstring dns) {
    updateDns(get_string(dns));
}

extern "C"
JNIEXPORT void JNICALL
Java_com_follow_clash_core_Core_invokeAction(JNIEnv *env, jobject thiz, jstring data, jobject cb) {
    const auto interface = new_global(cb);
    invokeAction(interface, get_string(data));
}

extern "C"
JNIEXPORT void JNICALL
Java_com_follow_clash_core_Core_setEventListener(JNIEnv *env, jobject thiz, jobject cb) {
    if (cb != nullptr) {
        const auto interface = new_global(cb);
        setEventListener(interface);
    } else {
        setEventListener(nullptr);
    }
}

extern "C"
JNIEXPORT jstring JNICALL
Java_com_follow_clash_core_Core_getTraffic(JNIEnv *env, jobject thiz,
                                           const jboolean only_statistics_proxy) {
    return new_string(getTraffic(only_statistics_proxy));
}

extern "C"
JNIEXPORT jstring JNICALL
Java_com_follow_clash_core_Core_getTotalTraffic(JNIEnv *env, jobject thiz,
                                                const jboolean only_statistics_proxy) {
    return new_string(getTotalTraffic(only_statistics_proxy));
}

extern "C"
JNIEXPORT void JNICALL
Java_com_follow_clash_core_Core_suspended(JNIEnv *env, jobject thiz, jboolean suspended) {
    suspend(suspended);
}

// --- ADDED: ZIVPN Turbo Native Launcher ---
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vector>

extern "C"
JNIEXPORT jint JNICALL
Java_com_follow_clash_core_Core_startZivpnTun(JNIEnv *env, jobject thiz, 
                                              jstring binaryPath, 
                                              jint fd, 
                                              jstring address, 
                                              jstring netmask, 
                                              jstring socksServer, 
                                              jstring udpgwAddr,
                                              jstring dnsgwAddr) {
    const char *binary_path_cstr = get_string(binaryPath);
    const char *address_cstr = get_string(address);
    const char *netmask_cstr = get_string(netmask);
    const char *socks_server_cstr = get_string(socksServer);
    const char *udpgw_cstr = get_string(udpgwAddr);
    const char *dnsgw_cstr = get_string(dnsgwAddr);

    pid_t pid = fork();
    if (pid == 0) {
        // Child process
        char fd_str[16];
        sprintf(fd_str, "%d", fd);

        std::vector<char*> args;
        args.push_back(strdup(binary_path_cstr));
        
        args.push_back(strdup("--tunfd"));
        args.push_back(strdup(fd_str));
        
        args.push_back(strdup("--netif-ipaddr"));
        args.push_back(strdup(address_cstr));
        
        args.push_back(strdup("--netif-netmask"));
        args.push_back(strdup(netmask_cstr));
        
        args.push_back(strdup("--socks-server-addr"));
        args.push_back(strdup(socks_server_cstr));

        if (strlen(udpgw_cstr) > 0) {
            args.push_back(strdup("--udpgw-remote-server-addr"));
            args.push_back(strdup(udpgw_cstr));
        }

        if (strlen(dnsgw_cstr) > 0) {
            args.push_back(strdup("--dnsgw"));
            args.push_back(strdup(dnsgw_cstr));
        }

        args.push_back(strdup("--loglevel"));
        args.push_back(strdup("notice"));

        args.push_back(nullptr);

        execv(binary_path_cstr, args.data());
        _exit(127); // If execv fails
    }
    
    return (jint)pid;
}
// ------------------------------------------

static jmethodID m_tun_interface_protect;
static jmethodID m_tun_interface_resolve_process;
static jmethodID m_invoke_interface_result;


static void release_jni_object_impl(void *obj) {
    ATTACH_JNI();
    del_global(static_cast<jobject>(obj));
}

static void free_string_impl(char *str) {
    free(str);
}

static void call_tun_interface_protect_impl(void *tun_interface, const int fd) {
    ATTACH_JNI();
    env->CallVoidMethod(static_cast<jobject>(tun_interface),
                        m_tun_interface_protect,
                        fd);
}

static char *
call_tun_interface_resolve_process_impl(void *tun_interface, const int protocol,
                                        const char *source,
                                        const char *target,
                                        const int uid) {
    ATTACH_JNI();
    const auto packageName = reinterpret_cast<jstring>(env->CallObjectMethod(
        static_cast<jobject>(tun_interface),
        m_tun_interface_resolve_process,
        protocol,
        new_string(source),
        new_string(target),
        uid));
    return get_string(packageName);
}

static void call_invoke_interface_result_impl(void *invoke_interface, const char *data) {
    ATTACH_JNI();
    env->CallVoidMethod(static_cast<jobject>(invoke_interface),
                        m_invoke_interface_result,
                        new_string(data));
}

extern "C"
JNIEXPORT jint JNICALL
JNI_OnLoad(JavaVM *vm, void *) {
    JNIEnv *env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6) != JNI_OK) {
        return JNI_ERR;
    }

    initialize_jni(vm, env);

    const auto c_tun_interface = find_class("com/follow/clash/core/TunInterface");

    const auto c_invoke_interface = find_class("com/follow/clash/core/InvokeInterface");

    m_tun_interface_protect = find_method(c_tun_interface, "protect", "(I)V");
    m_tun_interface_resolve_process = find_method(c_tun_interface, "resolverProcess",
                                                  "(ILjava/lang/String;Ljava/lang/String;I)Ljava/lang/String;");
    m_invoke_interface_result = find_method(c_invoke_interface, "onResult",
                                            "(Ljava/lang/String;)V");


    protect_func = &call_tun_interface_protect_impl;
    resolve_process_func = &call_tun_interface_resolve_process_impl;
    result_func = &call_invoke_interface_result_impl;
    release_object_func = &release_jni_object_impl;
    free_string_func = &free_string_impl;

    return JNI_VERSION_1_6;
}
#else
extern "C"
JNIEXPORT void JNICALL
Java_com_follow_clash_core_Core_startTun(JNIEnv *env, jobject thiz, jint fd, jobject cb,
                                         jstring stack, jstring address, jstring dns) {
}

extern "C"
JNIEXPORT void JNICALL
Java_com_follow_clash_core_Core_stopTun(JNIEnv *env, jobject thiz) {
}

extern "C"
JNIEXPORT void JNICALL
Java_com_follow_clash_core_Core_invokeAction(JNIEnv *env, jobject thiz, jstring data, jobject cb) {
}

extern "C"
JNIEXPORT void JNICALL
Java_com_follow_clash_core_Core_forceGC(JNIEnv *env, jobject thiz) {
}

extern "C"
JNIEXPORT void JNICALL
Java_com_follow_clash_core_Core_updateDNS(JNIEnv *env, jobject thiz, jstring dns) {
}

extern "C"
JNIEXPORT void JNICALL
Java_com_follow_clash_core_Core_setEventListener(JNIEnv *env, jobject thiz, jobject cb) {
}

extern "C"
JNIEXPORT jstring JNICALL
Java_com_follow_clash_core_Core_getTraffic(JNIEnv *env, jobject thiz,
                                           const jboolean only_statistics_proxy) {
}
extern "C"
JNIEXPORT jstring JNICALL
Java_com_follow_clash_core_Core_getTotalTraffic(JNIEnv *env, jobject thiz,
                                                const jboolean only_statistics_proxy) {
}

extern "C"
JNIEXPORT void JNICALL
Java_com_follow_clash_core_Core_suspended(JNIEnv *env, jobject thiz, jboolean suspended) {
}
#endif
