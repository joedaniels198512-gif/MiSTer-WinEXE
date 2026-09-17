/* SS1 DirectShow WaveOut renderer — private CLSID, PCM only.
 * Tune buffering here before touching any other audio subsystem.
 *
 * Total queued audio ≈ SS1_WO_BUFFERS * SS1_WO_BUFFER_MS milliseconds.
 */
#ifndef SS1_WINEXE_WAVEOUT_H
#define SS1_WINEXE_WAVEOUT_H

#include <basetyps.h>
#include <guiddef.h>

/* {B7E3C101-5A42-4D8F-9C1E-A1B2C3D4E5F6} */
DEFINE_GUID(CLSID_SS1WaveOut,
    0xb7e3c101, 0x5a42, 0x4d8f, 0x9c, 0x1e, 0xa1, 0xb2, 0xc3, 0xd4, 0xe5, 0xf6);

#define SS1_WO_FILTER_NAME L"SS1 WaveOut Renderer"
#define SS1_WO_PIN_NAME    L"Audio Input"
#define SS1_WO_PIN_ID      L"in"

#define SS1_WO_BUFFERS    6
#define SS1_WO_BUFFER_MS  12

#define SS1_WO_DLL_NAME   "ss1waveout.ax"

#endif
