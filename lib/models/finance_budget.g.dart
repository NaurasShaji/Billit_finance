// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'finance_budget.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FinanceBudgetAdapter extends TypeAdapter<FinanceBudget> {
  @override
  final int typeId = 21;

  @override
  FinanceBudget read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FinanceBudget(
      id: fields[0] as String,
      name: fields[1] as String,
      accountId: fields[2] as String,
      categoryId: fields[3] as String?,
      periodStart: fields[4] as DateTime,
      periodEnd: fields[5] as DateTime,
      budgetPaise: fields[6] as int,
      active: fields[7] as bool,
      notes: fields[8] as String,
      createdAt: fields[9] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, FinanceBudget obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.accountId)
      ..writeByte(3)
      ..write(obj.categoryId)
      ..writeByte(4)
      ..write(obj.periodStart)
      ..writeByte(5)
      ..write(obj.periodEnd)
      ..writeByte(6)
      ..write(obj.budgetPaise)
      ..writeByte(7)
      ..write(obj.active)
      ..writeByte(8)
      ..write(obj.notes)
      ..writeByte(9)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinanceBudgetAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
