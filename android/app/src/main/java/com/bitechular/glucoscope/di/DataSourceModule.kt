package com.bitechular.glucoscope.di

import com.bitechular.glucoscope.data.datasource.DataSourceService
import com.bitechular.glucoscope.data.datasource.RealtimeDataRepository
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DataSourceModule {

    @Provides
    @Singleton
    fun provideDataSourceService() = DataSourceService()

    @Provides
    @Singleton
    fun provideGlucoseRepository(dataSo: DataSourceService): RealtimeDataRepository =
        RealtimeDataRepository(dataSo)
}