// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payslip.dart';

class PayslipAdapter extends TypeAdapter<Payslip> {
  @override
  final int typeId = 20;

  @override
  Payslip read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < count; i++) reader.readByte(): reader.read(),
    };
    return Payslip(
      id: fields[0] as String,
      payrollRunId: fields[1] as String,
      employeeId: fields[2] as String,
      payType: fields[3] as String,
      basePaise: fields[4] as int? ?? 0,
      allowancesPaise: fields[5] as int? ?? 0,
      deductionsPaise: fields[6] as int? ?? 0,
      payableDays: fields[7] as double? ?? 0,
      paidPaise: fields[8] as int? ?? 0,
      status: fields[9] as String? ?? 'draft',
      generatedAt: fields[10] as DateTime? ?? DateTime.now(),
      paidAt: fields[11] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Payslip obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.payrollRunId)
      ..writeByte(2)
      ..write(obj.employeeId)
      ..writeByte(3)
      ..write(obj.payType)
      ..writeByte(4)
      ..write(obj.basePaise)
      ..writeByte(5)
      ..write(obj.allowancesPaise)
      ..writeByte(6)
      ..write(obj.deductionsPaise)
      ..writeByte(7)
      ..write(obj.payableDays)
      ..writeByte(8)
      ..write(obj.paidPaise)
      ..writeByte(9)
      ..write(obj.status)
      ..writeByte(10)
      ..write(obj.generatedAt)
      ..writeByte(11)
      ..write(obj.paidAt);
  }
}
