// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'finance_recurring_template.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FinanceRecurringTemplateAdapter
    extends TypeAdapter<FinanceRecurringTemplate> {
  @override
  final int typeId = 22;

  @override
  FinanceRecurringTemplate read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FinanceRecurringTemplate(
      id: fields[0] as String,
      name: fields[1] as String,
      transactionType: fields[2] as String,
      debitAccountId: fields[3] as String,
      creditAccountId: fields[4] as String,
      amountPaise: fields[5] as int,
      interval: fields[6] as String,
      nextDueDate: fields[7] as DateTime,
      endDate: fields[8] as DateTime?,
      categoryId: fields[9] as String?,
      partyId: fields[10] as String?,
      memo: fields[11] as String,
      active: fields[12] as bool,
      createdAt: fields[13] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, FinanceRecurringTemplate obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.transactionType)
      ..writeByte(3)
      ..write(obj.debitAccountId)
      ..writeByte(4)
      ..write(obj.creditAccountId)
      ..writeByte(5)
      ..write(obj.amountPaise)
      ..writeByte(6)
      ..write(obj.interval)
      ..writeByte(7)
      ..write(obj.nextDueDate)
      ..writeByte(8)
      ..write(obj.endDate)
      ..writeByte(9)
      ..write(obj.categoryId)
      ..writeByte(10)
      ..write(obj.partyId)
      ..writeByte(11)
      ..write(obj.memo)
      ..writeByte(12)
      ..write(obj.active)
      ..writeByte(13)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinanceRecurringTemplateAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
