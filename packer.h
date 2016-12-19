#ifndef _PETOY_PACKER_H_
#define _PETOY_PACKER_H_

#include <string>
#include <vector>
#include <windows.h>
#include <winnt.h>
#include "common.h"
#include "shell.h"

namespace petoy {

class Packer
{
public:
	Packer();
	~Packer();

	// ����PE�ļ����ڴ�
    EC load(const std::string &filename);
	// �ӿ�
    EC pack(const std::string &savename);
	// �ѿ�
    EC unpack(const std::string &savename);

private:
    size_t alignSize(size_t n, size_t align)
    {
		if (!n) return 0;
        return (n + align - 1) / align * align;
    }

    void *RvaPtr(size_t rva) { return _imageBase + rva; }
    
	size_t minSectionSize(const void *data, size_t len)
	{
		const char *buf = (const char *)data;
		while (!buf[len - 1] && len > 0)
			len--;
		return len;
	}
	void packImport(void);
	void packBaseReloc(void);
	void mergeBlock(char *data, size_t *len);
	size_t getBlockListSize(void);
	void clearSectionName(void);

	bool canSectionEncode(const std::string &name);
	size_t encode(char *dst, const char *src, size_t len);
	size_t decode(char *dst, const char *src, size_t len);
	
    
	PIMAGE_DOS_HEADER _dosHeader;
    PIMAGE_NT_HEADERS32 _ntHeaders;
    PIMAGE_SECTION_HEADER _secHeaders;

    char *_imageBase;
    size_t _imageSize;
    char *_extendBase;
    size_t _extendSize;

	std::vector<ToyBlockPtr> _toyBlockList; // ����ǵ����ݿ�
};

} // namespace petoy

#endif // _PETOY_PACKER_H_
