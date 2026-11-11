// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'finance_posting.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FinancePostingAdapter extends TypeAdapter<FinancePosting> {
  @override
  final int typeId = 12;

  @override
  FinancePosting read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FinancePosting(
      id: fields[0] as String,
      transactionId: fields[1] as String,
      accountId: fields[2] as String,
      debitPaise: fields[3] as int,
      creditPaise: fields[4] as int,
      partyId: fields[5] as String?,
      categoryId: fields[6] as String?,
      memo: fields[7] as String
    );
  }

  @override
  void write(BinaryWriter writer, FinancePosting obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.transactionId)
      ..writeByte(2)
      ..write(obj.accountId)
      ..writeByte(3)
      ..write(obj.debitPaise)
      ..writeByte(4)
      ..write(obj.creditPaise)
      ..writeByte(5)
      ..write(obj.partyId)
      ..writeByte(6)
      ..write(obj.categoryId)
      ..writeByte(7)
      ..write(obj.memo);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinancePostingAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
