#!/bin/bash
#
# Nyktelios 0.1
# 
# Copyright (C) 2008 by Mateo Matachana Lopez
#  <mat30.mail gmail.com>
# 
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 3 of the License, or
#  (at your option) any later version.
#

WORKING_DIR="/nyktelios/working/"

CREATED_DIRS="${WORKING_DIR}/info/created-dirs"
NYK_TMP_DIR="${WORKING_DIR}/tmp/"
NYK_SVN_DIR="/nyktelios/svn/"

NYK_TARGETS=( "${NYK_SVN_DIR}/trunk" ) # All SVN dir's where nyktelios must
                                       # generate a build.
NYK_TARGETS_CONF=( "--prefix=/usr " )  # ./configure options for each build

# Where store the generated packages 

NYK_TARGETS_DIRS=( "${WORKING_DIR}/nightly/build/" )

function nyk_check_env {
	# Creamos el directorio temporal si procede

	mkdir -p "${NYK_TMP_DIR}"
}

function nyk_preserve_target {
#FIXME Esto fallaría si usamos más de un target. Para un solo target funciona
#      bien

	destination_dir="${NYK_TARGETS_DIRS[$1]}"

	# Creamos el directorio con la fecha de hoy

	hist_dir_tmp=`date +"hist-%d-%m-%Y"`
	hist_dir="${destination_dir}/${hist_dir_tmp}"

	mkdir -p ${hist_dir}
	
	# Movemos la última build al directorio con fecha de hoy

	cp ${destination_dir}/latest/* "${hist_dir}"

	# Eliminamos la entrada historica que toque

	remove_hist=`tac ${CREATED_DIRS} | tail -n 1`

	rm "${remove_hist}/binaries-package.tar.gz"
	rm "${remove_hist}/source-package.tar.gz"
	rm "${remove_hist}/build-info"

	rmdir "${remove_hist}"

	echo "${hist_dir}" >> "${CREATED_DIRS}"
	tail -n 5 ${CREATED_DIRS} > ${CREATED_DIRS}-tmp
	mv ${CREATED_DIRS}-tmp ${CREATED_DIRS}

	
}

function nyk_compile_target {

	i=$1
	target_dir=${NYK_TARGETS[${i}]}
	
	echo "Comenzando a compilar $target_dir ..."
	configure_params=${NYK_TARGETS_CONF[$i]} 
	destination_dir="${NYK_TARGETS_DIRS[$i]}/latest/"

	# Eliminamos la ultima build
	rm "${destination_dir}/*"

	echo "Creando directorio de destino (si procede)..."
	mkdir -p $destination_dir

	cd $target_dir
	
	echo "Ejecutando make distclean para tener un entorno limpio..."
	make --directory=$target_dir distclean &> /dev/null	
	
	echo "Ejecutando script configure..."
	${target_dir}/configure ${configure_params} &> "${NYK_TMP_DIR}configure-output"

	if [ "$?" != 0 ]; then
		echo "FAILED CONFIGURE" > "${destination_dir}/build-info"
		cat "${NYK_TMP_DIR}configure-output" >> "${destination_dir}/build-info"
		echo "El script configure ha fallado, se aborta la construccion"
		exit
	fi

	echo "Ejecutando make..."
	
	make --directory=${target_dir} &> "${NYK_TMP_DIR}make-all-output"

	if [ "$?" != 0 ]; then
		echo "FAILED MAKE ALL" > "${destination_dir}/build-info"
		cat "${NYK_TMP_DIR}make-all-output" >> "${destination_dir}/build-info"
		echo "make all ha fallado, se aborta la construccion"
		exit
	fi

	echo "Instalando en el directorio temporal..."

	mkdir -p "${NYK_TMP_DIR}/build"
	make --directory=${target_dir} DESTDIR="${NYK_TMP_DIR}/build" install &> "${NYK_TMP_DIR}make-install-output"

	if [ "$?" != 0 ]; then
		echo "FAILED MAKE INSTALL" > "${destination_dir}/build-info"
		cat "${NYK_TMP_DIR}make-install-output" >> "${destination_dir}/build-info"
		echo "make install ha fallado, se aborta la construccion"
		exit
	fi

	package_name="tmp-build.tar"

	cd "${NYK_TMP_DIR}/build" 

	echo "Creando empaquetando temporal..."

	tar -cf $package_name *
	gzip $package_name
	
	make --directory=${target_dir} dist &> "${NYK_TMP_DIR}make-dist-output"

	if [ "$?" != 0 ]; then
		echo "FAILED MAKE DIST" > "${destination_dir}/build-info"
		cat "${NYK_TMP_DIR}make-dist-output" >> "${destination_dir}/build-info"
		echo "make dist ha fallado, se aborta la construccion"
		exit
	fi

	mv $target_dir/*.tar.gz "${NYK_TMP_DIR}/build/src-build.tar.gz"

	echo "Moviendo paquetes a destino..."

	mv "${NYK_TMP_DIR}/build/src-build.tar.gz" "${destination_dir}/source-package.tar.gz"
	
	mv "${NYK_TMP_DIR}/build/tmp-build.tar.gz" "${destination_dir}/binaries-package.tar.gz"

	echo "OK" > "${destination_dir}/build-info"

	echo "Limpiando archivos temporales..."

	rm -R "${NYK_TMP_DIR}"
}



nyk_check_env

cd $NYK_SVN_DIR

# Actualizamos el repositorio SVN

svn update > "${NYK_TMP_DIR}/resultados"
LINEAS=`cat "${NYK_TMP_DIR}/resultados" | wc -l`

if [ "${LINEAS}" == "1" ]; then
	# El repositorio no ha sufrido cambios

	for ((i=0;i<1;i++)); do
		nyk_preserve_target $i
	done
else
	# El repositorio ha cambiado, tenemos que recompilar

	for ((i=0;i<1;i++)); do
		nyk_preserve_target $i
		nyk_compile_target $i
	done
fi

