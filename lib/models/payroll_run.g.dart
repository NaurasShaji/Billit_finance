// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payroll_run.dart';

class PayrollRunAdapter extends TypeAdapter<PayrollRun> {
  @override
  final int typeId = 19;

  @override
  PayrollRun read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < count; i++) reader.readByte(): reader.read(),
    };
    return PayrollRun(
      id: fields[0] as String,
      periodStart: fields[1] as DateTime,
      periodEnd: fields[2] as DateTime,
      status: fields[3] as String? ?? 'draft',
      createdAt: fields[4] as DateTime? ?? DateTime.now(),
      approvedAt: fields[5] as DateTime?,
      paidAt: fields[6] as DateTime?,
      totalGrossPaise: fields[7] as int? ?? 0,
      totalDeductionsPaise: fields[8] as int? ?? 0,
      totalNetPaise: fields[9] as int? ?? 0,
      memo: fields[10] as String? ?? '',
    );
  }

  @override
  void write(BinaryWriter writer, PayrollRun obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.periodStart)
      ..writeByte(2)
      ..write(obj.periodEnd)
      ..writeByte(3)
      ..write(obj.status)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.approvedAt)
      ..writeByte(6)
      ..write(obj.paidAt)
      ..writeByte(7)
      ..write(obj.totalGrossPaise)
      ..writeByte(8)
      ..write(obj.totalDeductionsPaise)
      ..writeByte(9)
      ..write(obj.totalNetPaise)
      ..writeByte(10)
      ..write(obj.memo);
  }
}
