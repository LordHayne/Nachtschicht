/*
 * steamwebhelper wrapper for Steam under Wine on macOS.
 *
 * Steam's UI is a Chromium (CEF) browser, steamwebhelper.exe. Under Wine 11 on macOS its separate
 * GPU and renderer processes never get their pixels into the window, so Steam stays black, and its
 * separate network process trips over Wine's TLS. Steam doesn't forward --single-process to CEF, so
 * this tiny program takes steamwebhelper.exe's place and starts the real one (renamed to
 * steamwebhelper_real.exe) with the two flags prepended. Approach from notpop/steam-on-m1-wine (MIT).
 *
 * Build: x86_64-w64-mingw32-gcc -O2 -municode -mwindows -static -o steamwebhelper.exe steamwebhelper-wrapper.c
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <wchar.h>

#define EXTRA_FLAGS L"--disable-gpu --single-process"
#define REAL_BINARY L"steamwebhelper_real.exe"

/* The command line without our own program path (first token, possibly quoted). */
static const wchar_t *arguments(void)
{
    const wchar_t *cmd = GetCommandLineW();
    int quoted = 0;
    for (; *cmd; ++cmd) {
        if (*cmd == L'"') quoted = !quoted;
        else if (*cmd == L' ' && !quoted) break;
    }
    while (*cmd == L' ') ++cmd;
    return cmd;
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR cmdline, int show)
{
    (void)instance; (void)previous; (void)cmdline; (void)show;

    wchar_t real[MAX_PATH];
    DWORD len = GetModuleFileNameW(NULL, real, MAX_PATH);
    wchar_t *slash = wcsrchr(real, L'\\');
    if (len == 0 || len >= MAX_PATH || !slash) return 1;
    if ((size_t)(slash - real) + 1 + wcslen(REAL_BINARY) >= MAX_PATH) return 1;
    wcscpy(slash + 1, REAL_BINARY);

    const wchar_t *args = arguments();
    size_t size = wcslen(real) + wcslen(EXTRA_FLAGS) + wcslen(args) + 8;
    wchar_t *line = HeapAlloc(GetProcessHeap(), 0, size * sizeof(wchar_t));
    if (!line) return 1;
    _snwprintf(line, size, L"\"%ls\" %ls %ls", real, EXTRA_FLAGS, args);

    STARTUPINFOW startup = { .cb = sizeof(startup) };
    PROCESS_INFORMATION process;
    if (!CreateProcessW(real, line, NULL, NULL, TRUE, 0, NULL, NULL, &startup, &process)) return 1;

    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(process.hProcess, &code);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return (int)code;
}
