#pragma once

#include <array>

// Uses the buffered SCSI pass-through types declared in SPTIUtil.h.
namespace SanDisk55DD
{
	enum Sensor { Nand1, Nand2, Nand3, Nand4, Maximum, Minimum, BoardA, BoardB, SensorCount };
	constexpr int UnknownTemperature = -1000;
	using SensorReadings = std::array<int, SensorCount>;
	constexpr SensorReadings UnknownSensors = {
		UnknownTemperature, UnknownTemperature, UnknownTemperature, UnknownTemperature,
		UnknownTemperature, UnknownTemperature, UnknownTemperature, UnknownTemperature
	};

	struct Capabilities
	{
		DWORD LogicalSector = 0;
		DWORD PhysicalSector = 0;
		int Trim = -1;
		int ReadCache = -1;
		int WriteCache = -1;
	};

	struct Readings
	{
		char Serial[253]{};
		int HostReads = -1;
		int Temperature = UnknownTemperature;
		SensorReadings Sensors = UnknownSensors;
		char InternalFirmware[9]{};
	};

	inline DWORD ReadScsi(HANDLE handle, const BYTE* command, BYTE commandLength,
		DWORD allocationLength, SCSI_PASS_THROUGH_WITH_BUFFERS& reply)
	{
		reply = {};
		const DWORD dataOffset = offsetof(SCSI_PASS_THROUGH_WITH_BUFFERS, DataBuf);
		reply.Spt.Length = sizeof(SCSI_PASS_THROUGH);
		reply.Spt.CdbLength = commandLength;
		reply.Spt.SenseInfoLength = sizeof(reply.SenseBuf);
		reply.Spt.DataIn = SCSI_IOCTL_DATA_IN;
		reply.Spt.DataTransferLength = allocationLength;
		reply.Spt.TimeOutValue = 2;
		reply.Spt.DataBufferOffset = dataOffset;
		reply.Spt.SenseInfoOffset = offsetof(SCSI_PASS_THROUGH_WITH_BUFFERS, SenseBuf);
		memcpy(reply.Spt.Cdb, command, commandLength);

		DWORD returned = 0;
		const DWORD bufferLength = dataOffset + allocationLength;
		if (!::DeviceIoControl(handle, IOCTL_SCSI_PASS_THROUGH, &reply, bufferLength,
			&reply, bufferLength, &returned, nullptr) || reply.Spt.ScsiStatus || returned <= dataOffset)
		{
			return 0;
		}
		const DWORD transferred = reply.Spt.DataTransferLength;
		return (transferred <= returned - dataOffset && transferred <= allocationLength) ? transferred : 0;
	}

	inline bool ReadLogPage(HANDLE handle, BYTE page, DWORD pageLength,
		SCSI_PASS_THROUGH_WITH_BUFFERS& reply)
	{
		// This firmware rejects larger LOG SENSE allocation lengths over UASP.
		const BYTE command[] = {0x4D, 0, BYTE(0x40 | page), 0, 0, 0, 0, 0, 252, 0};
		return ReadScsi(handle, command, sizeof(command), 252, reply) >= pageLength
			&& (reply.DataBuf[0] & 0x7F) == page && reply.DataBuf[1] == 0
			&& (DWORD(reply.DataBuf[2]) * 256 + reply.DataBuf[3] + 4) == pageLength;
	}

	inline Capabilities ReadCapabilities(HANDLE handle)
	{
		Capabilities info;
		DWORD returned = 0;
		STORAGE_PROPERTY_QUERY query{};
		query.QueryType = PropertyStandardQuery;
		query.PropertyId = StorageAccessAlignmentProperty;
		STORAGE_ACCESS_ALIGNMENT_DESCRIPTOR alignment{};
		if (::DeviceIoControl(handle, IOCTL_STORAGE_QUERY_PROPERTY, &query, sizeof(query),
			&alignment, sizeof(alignment), &returned, nullptr) && returned >= sizeof(alignment))
		{
			info.LogicalSector = alignment.BytesPerLogicalSector;
			info.PhysicalSector = alignment.BytesPerPhysicalSector;
		}
		query.PropertyId = StorageDeviceTrimProperty;
		DEVICE_TRIM_DESCRIPTOR trim{};
		if (::DeviceIoControl(handle, IOCTL_STORAGE_QUERY_PROPERTY, &query, sizeof(query),
			&trim, sizeof(trim), &returned, nullptr) && returned >= sizeof(trim))
		{
			info.Trim = trim.TrimEnabled != FALSE;
		}

		SCSI_PASS_THROUGH_WITH_BUFFERS reply{};
		const BYTE modeSense[] = {0x1A, 0, 0x08, 0, 64, 0};
		const DWORD length = ReadScsi(handle, modeSense, sizeof(modeSense), 64, reply);
		const DWORD page = 4 + reply.DataBuf[3];
		if (length >= page + 3 && DWORD(reply.DataBuf[0]) + 1 >= page + 3
			&& (reply.DataBuf[page] & 0x7F) == 0x08 && reply.DataBuf[page + 1] >= 1)
		{
			const BYTE flags = reply.DataBuf[page + 2];
			info.ReadCache = (flags & 0x01) == 0;
			info.WriteCache = (flags & 0x04) != 0;
		}
		return info;
	}

	inline bool Read(HANDLE handle, Readings& readings)
	{
		readings = {};
		SCSI_PASS_THROUGH_WITH_BUFFERS reply{};
		const BYTE inquiry[] = {0x12, 0, 0, 0, 36, 0};
		if (ReadScsi(handle, inquiry, sizeof(inquiry), 36, reply) < 36
			|| memcmp(reply.DataBuf + 8, "SanDisk Extreme 55DD    0010", 28) != 0)
		{
			return false;
		}

		const BYTE serialInquiry[] = {0x12, 1, 0x80, 0, 252, 0};
		const DWORD serialReplyLength = ReadScsi(handle, serialInquiry, sizeof(serialInquiry), 252, reply);
		const DWORD serialLength = DWORD(reply.DataBuf[2]) * 256 + reply.DataBuf[3];
		if (serialReplyLength < 4 || reply.DataBuf[1] != 0x80 || serialLength == 0 || reply.DataBuf[4] == 0
			|| serialLength > serialReplyLength - 4)
		{
			return false;
		}
		memcpy(readings.Serial, reply.DataBuf + 4, serialLength);

		// Community-verified field layout for firmware 0010.
		// https://github.com/smartmontools/smartmontools/issues/526
		if (ReadLogPage(handle, 0x30, 169, reply) && reply.DataBuf[4] == 1)
		{
			const BYTE* counter = reply.DataBuf + 0x81;
			const DWORD gib = DWORD(counter[0]) | (DWORD(counter[1]) << 8)
				| (DWORD(counter[2]) << 16) | (DWORD(counter[3]) << 24);
			if (gib <= INT_MAX)
			{
				readings.HostReads = static_cast<int>(gib);
			}
		}
		if (ReadLogPage(handle, 0x31, 77, reply) && reply.DataBuf[4] == 1)
		{
			const BYTE* firmware = reply.DataBuf + 0x41;
			size_t digits = 0;
			while (digits < 8 && firmware[digits] >= '0' && firmware[digits] <= '9')
			{
				++digits;
			}
			if (digits == 8)
			{
				memcpy(readings.InternalFirmware, firmware, digits);
			}
		}
		if (ReadLogPage(handle, 0x32, 49, reply) && reply.DataBuf[4] == 1
			&& reply.DataBuf[5] == 0xFF && reply.DataBuf[6] == 0x11)
		{
			if (reply.DataBuf[7] < 100)
			{
				readings.Temperature = reply.DataBuf[7];
			}
			const BYTE sensorOffsets[SensorCount] = {8, 9, 10, 11, 12, 13, 16, 21};
			for (size_t i = 0; i < SensorCount; ++i)
			{
				const BYTE temperature = reply.DataBuf[sensorOffsets[i]];
				if (temperature < 100)
				{
					readings.Sensors[i] = temperature;
				}
			}
		}
		return true;
	}
}
